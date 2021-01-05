# frozen_string_literal: true

require 'digest'

ZERO_HASH = Eth2ForkChoice::ZERO_HASH

def index_to_hash(i)
  Digest::SHA256.hexdigest([i].pack('Q<'))
end

RSpec.describe Eth2ForkChoice do
  context 'No Vote' do
    it 'can find head' do
      balances = []

      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # The head should always start at the finalized block.
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(ZERO_HASH)

      # Insert block 2 into the tree and verify head is at 2:
      #         0
      #        /
      #       2 <- head
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 1 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             3
      f.process_block(0, index_to_hash(3), index_to_hash(1), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 4 into the tree and verify head is at 4:
      #            0
      #           / \
      #          2  1
      #          |  |
      #  head -> 4  3
      f.process_block(0, index_to_hash(4), index_to_hash(2), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(4))

      # Insert block 5 with justified epoch of 2, verify head is still at 4.
      #            0
      #           / \
      #          2  1
      #          |  |
      #  head -> 4  3
      #          |
      #          5 <- justified epoch = 2
      f.process_block(0, index_to_hash(5), index_to_hash(4), 2, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(4))

      expect { f.head(1, index_to_hash(5), balances, 1) }.to raise_error { |e|
        e.message == 'head at slot 0 with weight 0 is not eligible, finalized_epoch 1 != 1, justified_epoch 2 != 1'
      }

      # Set the justified epoch to 2 and start block to 5 to verify head is 5.
      #            0
      #           / \
      #          2  1
      #          |  |
      #          4  3
      #          |
      #          5 <- head
      r = f.head(2, index_to_hash(5), balances, 1)
      expect(r).to eq(index_to_hash(5))

      # Insert block 6 with justified epoch of 2, verify head is at 6.
      #            0
      #           / \
      #          2  1
      #          |  |
      #          4  3
      #          |
      #          5
      #          |
      #          6 <- head
      f.process_block(0, index_to_hash(6), index_to_hash(5), 2, 1)
      r = f.head(2, index_to_hash(5), balances, 1)
      expect(r).to eq(index_to_hash(6))
    end

    it 'compares same weight nodes by root' do
      balances = []

      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # Insert block 1 then block 2 into the tree and verify head is at 2:
      #            0
      #           / \
      #          1  2 <- head
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(1))
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 4 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             4
      # though index_to_hash(4) > index_to_hash(2)
      f.process_block(0, index_to_hash(4), index_to_hash(1), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is at 3:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             4
      # though index_to_hash(4) > index_to_hash(2)
      f.process_block(0, index_to_hash(3), index_to_hash(2), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(3))
    end
  end

  context 'Votes' do
    it 'can find head' do
      balances = [1, 1]

      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # The head should always start at the finalized block.
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(ZERO_HASH)

      # Insert block 2 into the tree and verify head is at 2:
      #         0
      #        /
      #       2 <- head
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 1 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Add a vote to block 1 of the tree and verify head is switched to 1:
      #            0
      #           / \
      #          2  1 <- +vote, new head
      f.process_attestation([0], index_to_hash(1), 2)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(1))

      # Add a vote to block 2 of the tree and verify head is switched to 2:
      #                     0
      #                    / \
      # vote, new head -> 2  1
      f.process_attestation([1], index_to_hash(2), 2)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             3
      f.process_block(0, index_to_hash(3), index_to_hash(1), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Move validator 0's vote from 1 to 3 and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1 <- old vote
      #             |
      #             3 <- new vote
      f.process_attestation([0], index_to_hash(3), 3)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(2))

      # Move validator 1's vote from 2 to 1 and verify head is switched to 3:
      #               0
      #              / \
      # old vote -> 2  1 <- new vote
      #                |
      #                3 <- head
      f.process_attestation([1], index_to_hash(1), 3)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(3))

      # Insert block 4 into the tree and verify head is at 4:
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4 <- head
      f.process_block(0, index_to_hash(4), index_to_hash(3), 1, 1)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(4))

      # Insert block 5 with justified epoch 2, it should be filtered out:
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4 <- head
      #            /
      #           5 <- justified epoch = 2
      f.process_block(0, index_to_hash(5), index_to_hash(4), 2, 2)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(4))

      # Insert block 6 with justified epoch 0:
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4 <- head
      #            / \
      #           5  6 <- justified epoch = 0
      f.process_block(0, index_to_hash(6), index_to_hash(4), 1, 1)

      # Moved 2 votes to block 5:
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4
      #            / \
      # 2 votes-> 5  6
      f.process_attestation([0, 1], index_to_hash(5), 4)

      # Inset blocks 7, 8 and 9:
      # 6 should still be the head, even though 5 has all the votes.
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4
      #            / \
      #           5  6 <- head
      #           |
      #           7
      #           |
      #           8
      #           |
      #           9
      f.process_block(0, index_to_hash(7), index_to_hash(5), 2, 2)
      f.process_block(0, index_to_hash(8), index_to_hash(7), 2, 2)
      f.process_block(0, index_to_hash(9), index_to_hash(8), 2, 2)
      r = f.head(1, ZERO_HASH, balances, 1)
      expect(r).to eq(index_to_hash(6))

      # Update fork choice justified epoch to 1 and start block to 5.
      # Verify 9 is the head:
      #            0
      #           / \
      #          2  1
      #             |
      #             3
      #             |
      #             4
      #            / \
      #           5  6
      #           |
      #           7
      #           |
      #           8
      #           |
      #           9 <- head
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(9))

      # Insert block 10 and 2 validators updated their vote to 9.
      # Verify 9 is the head:
      #             0
      #            / \
      #           2  1
      #              |
      #              3
      #              |
      #              4
      #             / \
      #            5  6
      #            |
      #            7
      #            |
      #            8
      #           / \
      # 2 votes->9  10
      f.process_block(0, index_to_hash(10), index_to_hash(8), 2, 2)
      f.process_attestation([0, 1], index_to_hash(9), 5)
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(9))

      # Add 3 more validators to the system.
      balances = [1, 1, 1, 1, 1]

      # The new validators voted for 10.
      f.process_attestation([2, 3, 4], index_to_hash(10), 5)
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(10))

      # Set the balances of the last 2 validators to 0.
      balances = [1, 1, 1, 0, 0]
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(9))

      # Set the balances back to normal.
      balances = [1, 1, 1, 1, 1]

      # The head should be back to 10.
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(10))

      # Remove the last 2 validators.
      balances = [1, 1, 1]

      # The head should be back to 9.
      r = f.head(2, index_to_hash(5), balances, 2)
      expect(r).to eq(index_to_hash(9))
    end
  end

  context 'FFG Updates' do
    it 'works for one branch' do
      balances = [1, 1]

      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 0, 0)

      # The head should always start at the finalized block.
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(ZERO_HASH)

      # Define the following tree:
      #            0 <- justified: 0, finalized: 0
      #            |
      #            1 <- justified: 0, finalized: 0
      #            |
      #            2 <- justified: 1, finalized: 0
      #            |
      #            3 <- justified: 2, finalized: 1
      f.process_block(1, index_to_hash(1), ZERO_HASH, 0, 0)
      f.process_block(2, index_to_hash(2), index_to_hash(1), 1, 0)
      f.process_block(3, index_to_hash(3), index_to_hash(2), 2, 0)

      # With starting justified epoch at 0, the head should be 3:
      #            0 <- start
      #            |
      #            1
      #            |
      #            2
      #            |
      #            3 <- head
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(3))

      # With starting justified epoch at 1, the head should be 2:
      #            0
      #            |
      #            1 <- start
      #            |
      #            2 <- head
      #            |
      #            3
      r = f.head(1, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(2))

      # With starting justified epoch at 2, the head should be 3:
      #            0
      #            |
      #            1
      #            |
      #            2 <- start
      #            |
      #            3 <- head
      r = f.head(2, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(3))
    end

    it 'works for two branches' do
      balances = [1, 1]

      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 0, 0)

      # The head should always start at the finalized block.
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(ZERO_HASH)

      # Define the following tree:
      #                                0
      #                               / \
      #  justified: 0, finalized: 0 -> 1   2 <- justified: 0, finalized: 0
      #                              |   |
      #  justified: 1, finalized: 0 -> 3   4 <- justified: 0, finalized: 0
      #                              |   |
      #  justified: 1, finalized: 0 -> 5   6 <- justified: 0, finalized: 0
      #                              |   |
      #  justified: 1, finalized: 0 -> 7   8 <- justified: 1, finalized: 0
      #                              |   |
      #  justified: 2, finalized: 0 -> 9  10 <- justified: 2, finalized: 0

      # Left branch.
      f.process_block(1, index_to_hash(1), ZERO_HASH, 0, 0)
      f.process_block(2, index_to_hash(3), index_to_hash(1), 1, 0)
      f.process_block(3, index_to_hash(5), index_to_hash(3), 1, 0)
      f.process_block(4, index_to_hash(7), index_to_hash(5), 1, 0)
      f.process_block(4, index_to_hash(9), index_to_hash(7), 2, 0)

      # Right branch.
      f.process_block(1, index_to_hash(2), ZERO_HASH, 0, 0)
      f.process_block(2, index_to_hash(4), index_to_hash(2), 1, 0)
      f.process_block(3, index_to_hash(6), index_to_hash(4), 1, 0)
      f.process_block(4, index_to_hash(8), index_to_hash(6), 1, 0)
      f.process_block(4, index_to_hash(10), index_to_hash(8), 2, 0)

      # With start at 0, the head should be 10:
      #           0  <-- start
      #          / \
      #         1   2
      #         |   |
      #         3   4
      #         |   |
      #         5   6
      #         |   |
      #         7   8
      #         |   |
      #         9  10 <-- head
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(10))

      # Add a vote to 1:
      #                 0
      #                / \
      #    +1 vote -> 1   2
      #               |   |
      #               3   4
      #               |   |
      #               5   6
      #               |   |
      #               7   8
      #               |   |
      #               9  10
      f.process_attestation([0], index_to_hash(1), 0)

      # With the additional vote to the left branch, the head should be 9:
      #           0  <-- start
      #          / \
      #         1   2
      #         |   |
      #         3   4
      #         |   |
      #         5   6
      #         |   |
      #         7   8
      #         |   |
      # head -> 9  10
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(9))

      # Add a vote to 2:
      #                 0
      #                / \
      #               1   2 <- +1 vote
      #               |   |
      #               3   4
      #               |   |
      #               5   6
      #               |   |
      #               7   8
      #               |   |
      #               9  10
      f.process_attestation([1], index_to_hash(2), 0)

      # With the additional vote to the right branch, the head should be 10:
      #           0  <-- start
      #          / \
      #         1   2
      #         |   |
      #         3   4
      #         |   |
      #         5   6
      #         |   |
      #         7   8
      #         |   |
      #         9  10 <-- head
      r = f.head(0, ZERO_HASH, balances, 0)
      expect(r).to eq(index_to_hash(10))

      r = f.head(1, index_to_hash(1), balances, 0)
      expect(r).to eq(index_to_hash(7))
    end
  end
end
