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
  end
end
