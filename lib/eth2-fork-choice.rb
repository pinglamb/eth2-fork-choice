# frozen_string_literal: true

require_relative 'eth2-fork-choice/version'

module Eth2ForkChoice
  ZERO_HASH = '0000000000000000000000000000000000000000000000000000000000000000'

  class UnknownJustifiedRoot < StandardError; end

  class Magic
    attr_reader :store, :balances, :votes

    def head(justified_epoch, justified_root, justified_state_balances, finalized_epoch)
      deltas = compute_deltas(justified_state_balances)
      @store.apply_weight_changes(justified_epoch, finalized_epoch, deltas)
      @balances = justified_state_balances
      @store.head(justified_root)
    end

    def process_block(slot, block_root, parent_root, justified_epoch, finalized_epoch)
      @store.insert(slot, block_root, parent_root, justified_epoch, finalized_epoch)
    end

    def process_attestation(validator_indices, block_root, target_epoch)
      validator_indices.each do |index|
        @votes[index] ||= Vote.new

        if @votes[index].next_root == ZERO_HASH || target_epoch > @votes[index].next_epoch
          @votes[index].next_epoch = target_epoch
          @votes[index].next_root = block_root
        end
      end
    end

    private

    def initialize(justified_epoch, finalized_epoch, finalized_root)
      @store =
        Store.new(justified_epoch: justified_epoch, finalized_epoch: finalized_epoch, finalized_root: finalized_root)
      @balances = []
      @votes = []
    end

    def compute_deltas(new_balances)
      old_balances = @balances

      deltas = [0] * @store.nodes_indices.size
      @votes.each.with_index do |vote, validator_index|
        # Skip if validator has never voted for current root and next root (ie. if the
        # votes are zero hash aka genesis block), there's nothing to compute.
        next if vote.nil? || (vote.current_root == ZERO_HASH && vote.next_root == ZERO_HASH)

        old_balance = old_balances[validator_index] || 0
        new_balance = new_balances[validator_index] || 0

        # Perform delta only if the validator's balance or vote has changed.
        if vote.current_root != vote.next_root || old_balance != new_balance
          # Ignore the vote if it's not known in `blockIndices`,
          # that means we have not seen the block before.
          if next_delta_index = @store.nodes_indices[vote.next_root]
            deltas[next_delta_index] += new_balance
          end

          if current_delta_index = @store.nodes_indices[vote.current_root]
            deltas[current_delta_index] -= old_balance
          end
        end

        vote.current_root = vote.next_root
      end

      deltas
    end
  end

  class Store
    attr_reader :nodes_indices, :nodes
    attr_accessor :justified_epoch, :finalized_epoch, :finalized_root

    def head(justified_root)
      justified_index = @nodes_indices[justified_root]
      raise UnknownJustifiedRoot if justified_index.nil?

      justified_node = @nodes[justified_index]
      best_descendent_index = justified_node.best_descendant
      best_descendent_index = justified_index if best_descendent_index.nil?
      best_node = @nodes[best_descendent_index]
      unless viable_for_head?(best_node)
        raise StandardError.new(
                "head at slot #{best_node.slot} with weight #{
                  (best_node.weight / 10e9).floor
                } is not eligible, finalized_epoch #{best_node.finalized_epoch} != #{
                  @finalized_epoch
                }, justified_epoch #{best_node.justified_epoch} != #{@justified_epoch}"
              )
      end

      best_node.root
    end

    def insert(slot, root, parent, justified_epoch, finalized_epoch)
      # Return if the block has been inserted into Store before.
      return unless @nodes_indices[root].nil?

      index = @nodes.size
      parent_index = @nodes_indices[parent]

      node =
        Node.new(
          slot: slot,
          root: root,
          parent: parent_index,
          justified_epoch: justified_epoch,
          finalized_epoch: finalized_epoch,
          best_child: nil,
          best_descendant: nil,
          weight: 0
        )

      @nodes_indices[root] = index
      @nodes << node

      update_best_child_and_descendant(parent_index, index) unless node.parent.nil?

      node
    end

    # applyWeightChanges iterates backwards through the nodes in store. It checks all nodes parent
    # and its best child. For each node, it updates the weight with input delta and
    # back propagate the nodes delta to its parents delta. After scoring changes,
    # the best child is then updated along with best descendant.
    def apply_weight_changes(justified_epoch, finalized_epoch, delta)
      # Update the justified / finalized epochs in store if necessary.
      if @justified_epoch != justified_epoch || @finalized_epoch != finalized_epoch
        @justified_epoch = justified_epoch
        @finalized_epoch = finalized_epoch
      end

      last_index = @nodes.size - 1

      # Iterate backwards through all index to node in store.
      last_index.downto(0) do |i|
        node = @nodes[i]

        # There is no need to adjust the balances or manage parent of the zero hash, it
        # is an alias to the genesis block.
        next if node == ZERO_HASH

        node_delta = delta[i]
        if node_delta < 0
          # A node's weight can not be negative but the delta can be negative.
          if node.weight + node_delta < 0
            node.weight = 0
          else
            # Subtract node's weight.
            node.weight -= node_delta.abs
          end
        else
          node.weight += node_delta
        end

        delta[node.parent] += node_delta unless node.parent.nil?
      end

      last_index.downto(0) do |i|
        node = @nodes[i]
        update_best_child_and_descendant(node.parent, i) unless node.parent.nil?
      end
    end

    private

    def initialize(justified_epoch:, finalized_epoch:, finalized_root:)
      @justified_epoch = justified_epoch
      @finalized_epoch = finalized_epoch
      @finalized_root = finalized_root
      @nodes_indices = {}
      @nodes = []
    end

    # updateBestChildAndDescendant updates parent node's best child and descendent.
    # It looks at input parent node and input child node and potentially modifies parent's best
    # child and best descendent indices.
    # There are four outcomes:
    # 1.)  The child is already the best child but it's now invalid due to a FFG change and should be removed.
    # 2.)  The child is already the best child and the parent is updated with the new best descendant.
    # 3.)  The child is not the best child but becomes the best child.
    # 4.)  The child is not the best child and does not become best child.
    def update_best_child_and_descendant(parent_index, child_index)
      parent = @nodes[parent_index]
      child = @nodes[child_index]

      child_leads_to_viable_head = leads_to_viable_head?(child)

      # Define 3 variables for the 3 outcomes mentioned above. This is to
      # set `parent.bestChild` and `parent.bestDescendant` to. These
      # aliases are to assist readability.
      change_to_none = [nil, nil]
      change_to_child = [child_index, child.best_descendant || child_index]
      no_change = [parent.best_child, parent.best_descendant]

      # All the comparison is still among child and best_child, not best_descendant
      result = nil
      if parent.best_child.nil?
        if child_leads_to_viable_head
          # If parent doesn't have a best child and the child is viable.
          result = change_to_child
        else
          # If parent doesn't have a best child and the child is not viable.
          result = no_change
        end
      else
        if parent.best_child == child_index && !child_leads_to_viable_head
          # If the child is already the best child of the parent but it's not viable for head,
          # we should remove it. (Outcome 1)
          result = change_to_none
        elsif parent.best_child == child_index
          # If the child is already the best child of the parent, set it again to ensure best
          # descendent of the parent is updated. (Outcome 2)
          result = change_to_child
        else
          best_child = @nodes[parent.best_child]

          # Is current parent's best child viable to be head? Based on justification and finalization rules.
          best_child_leads_to_viable_head = leads_to_viable_head?(best_child)

          if child_leads_to_viable_head && !best_child_leads_to_viable_head
            # The child leads to a viable head, but the current parent's best child doesnt.
            result = change_to_child
          elsif !child_leads_to_viable_head && best_child_leads_to_viable_head
            # The child doesn't lead to a viable head, the current parent's best child does.
            result = no_change
          elsif child.weight == best_child.weight
            # If both are viable, compare their weights.
            # Tie-breaker of equal weights by root. Larger root wins
            # FIXME Simplified comparison, just first 2 bytes
            child_root_bytes = [child.root].pack('H*').bytes
            best_child_root_bytes = [best_child.root].pack('H*').bytes
            child_root_gt_best_child_root =
              if child_root_bytes[0] == best_child_root_bytes[0]
                child_root_bytes[1] >= best_child_root_bytes[1]
              else
                child_root_bytes[0] > best_child_root_bytes[0]
              end
            if child_root_gt_best_child_root
              result = change_to_child
            else
              result = no_change
            end
          else
            if child.weight > best_child.weight
              result = change_to_child
            else
              result = no_change
            end
          end
        end
      end

      parent.best_child, parent.best_descendant = *result

      # puts [parent_index, child_index, parent.best_child, parent.best_descendant].inspect

      parent
    end

    # leadsToViableHead returns true if the node or the best descendent of the node is viable for head.
    # Any node with diff finalized or justified epoch than the ones in fork choice store
    # should not be viable to head.
    def leads_to_viable_head?(node)
      node.best_descendant.nil? ? viable_for_head?(node) : viable_for_head?(@nodes[node.best_descendant])
    end

    # viableForHead returns true if the node is viable to head.
    # Any node with diff finalized or justified epoch than the ones in fork choice store
    # should not be viable to head.
    def viable_for_head?(node)
      # `node` is viable if its justified epoch and finalized epoch are the same as the one in `Store`.
      # It's also viable if we are in genesis epoch.
      justified = @justified_epoch == node.justified_epoch || @justified_epoch == 0
      finalized = @finalized_epoch == node.finalized_epoch || @finalized_epoch == 0

      justified && finalized
    end
  end

  class Node
    attr_accessor :slot, :root, :parent, :justified_epoch, :finalized_epoch, :best_child, :best_descendant, :weight

    private

    def initialize(slot:, root:, parent:, justified_epoch:, finalized_epoch:, best_child:, best_descendant:, weight:)
      @slot = slot
      @root = root
      @parent = parent
      @justified_epoch = justified_epoch
      @finalized_epoch = finalized_epoch
      @best_child = best_child
      @best_descendant = best_descendant
      @weight = weight
    end
  end

  class Vote
    attr_accessor :current_root, :next_root, :next_epoch

    private

    def initialize
      @current_root = ZERO_HASH
      @next_root = ZERO_HASH
      @next_epoch = 0
    end
  end
end
