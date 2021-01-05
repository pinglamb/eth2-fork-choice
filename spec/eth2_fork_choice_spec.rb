# frozen_string_literal: true

require 'digest'

ZERO_HASH = Eth2ForkChoice::ZERO_HASH

def index_to_hash(i)
  Digest::SHA256.hexdigest([i].pack('Q<'))
end

RSpec.describe Eth2ForkChoice do
  context 'No Vote' do
    it 'can find head' do
      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # The head should always start at the finalized block.
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(ZERO_HASH)

      # Insert block 2 into the tree and verify head is at 2:
      #         0
      #        /
      #       2 <- head
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 1 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             3
      f.process_block(0, index_to_hash(3), index_to_hash(1), 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 4 into the tree and verify head is at 4:
      #            0
      #           / \
      #          2  1
      #          |  |
      #  head -> 4  3
      f.process_block(0, index_to_hash(4), index_to_hash(2), 1, 1)
      r = f.head(1, ZERO_HASH, 1)
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
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(4))

      expect { f.head(1, index_to_hash(5), 1) }.to raise_error { |e|
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
      r = f.head(2, index_to_hash(5), 1)
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
      r = f.head(2, index_to_hash(5), 1)
      expect(r).to eq(index_to_hash(6))
    end

    it 'compares same weight nodes by root' do
      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # Insert block 1 then block 2 into the tree and verify head is at 2:
      #            0
      #           / \
      #          1  2 <- head
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      expect(f.head(1, ZERO_HASH, 1)).to eq(index_to_hash(1))
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      expect(f.head(1, ZERO_HASH, 1)).to eq(index_to_hash(2))

      # Insert block 4 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             4
      # though index_to_hash(4) > index_to_hash(2)
      f.process_block(0, index_to_hash(4), index_to_hash(1), 1, 1)
      expect(f.head(1, ZERO_HASH, 1)).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is at 3:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             4
      # though index_to_hash(4) > index_to_hash(2)
      f.process_block(0, index_to_hash(3), index_to_hash(2), 1, 1)
      expect(f.head(1, ZERO_HASH, 1)).to eq(index_to_hash(3))
    end
  end

  context 'Votes' do
    it 'can find head' do
      f = Eth2ForkChoice::Magic.new(0, 0, ZERO_HASH)
      f.process_block(0, ZERO_HASH, nil, 1, 1)

      # The head should always start at the finalized block.
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(ZERO_HASH)

      # Insert block 2 into the tree and verify head is at 2:
      #         0
      #        /
      #       2 <- head
      f.process_block(0, index_to_hash(2), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 1 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      f.process_block(0, index_to_hash(1), ZERO_HASH, 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Add a vote to block 1 of the tree and verify head is switched to 1:
      #            0
      #           / \
      #          2  1 <- +vote, new head
      f.process_attestation([0], index_to_hash(1), 2)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(1))

      # Add a vote to block 2 of the tree and verify head is switched to 2:
      #                     0
      #                    / \
      # vote, new head -> 2  1
      f.process_attestation([1], index_to_hash(2), 2)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Insert block 3 into the tree and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1
      #             |
      #             3
      f.process_block(0, index_to_hash(3), index_to_hash(1), 1, 1)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Move validator 0's vote from 1 to 3 and verify head is still at 2:
      #            0
      #           / \
      #  head -> 2  1 <- old vote
      #             |
      #             3 <- new vote
      f.process_attestation([0], index_to_hash(3), 3)
      r = f.head(1, ZERO_HASH, 1)
      expect(r).to eq(index_to_hash(2))

      # Move validator 1's vote from 2 to 1 and verify head is switched to 3:
      #               0
      #              / \
      # old vote -> 2  1 <- new vote
      #                |
      #                3 <- head
      f.process_attestation([1], index_to_hash(1), 3)
      r = f.head(1, ZERO_HASH, 1)
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
      r = f.head(1, ZERO_HASH, 1)
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
      r = f.head(1, ZERO_HASH, 1)
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
      r = f.head(1, ZERO_HASH, 1)
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
      r = f.head(2, index_to_hash(5), 2)
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
      r = f.head(2, index_to_hash(5), 2)
      expect(r).to eq(index_to_hash(9))

      # Add 3 more validators to the system.
      # The new validators voted for 10.
      f.process_attestation([2, 3, 4], index_to_hash(10), 5)
      r = f.head(2, index_to_hash(5), 2)
      expect(r).to eq(index_to_hash(10))
    end
  end
end
