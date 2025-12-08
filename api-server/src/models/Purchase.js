// api-server/src/models/Purchase.js
const mongoose = require('mongoose');

const purchaseSchema = new mongoose.Schema({
  username: { 
    type: String, 
    required: true,
    index: true, // Index for searching by username
    trim: true
  },
  userid: { 
    type: String, 
    required: true,
    index: true // Index for searching by userid
  },
  price: { 
    type: Number, 
    required: true,
    min: 0
  },
  timestamp: { 
    type: Date, 
    default: Date.now,
    index: true // Index for sorting by date
  }
}, {
  timestamps: true, // Adds createdAt and updatedAt automatically
  collection: 'purchases'
});

// Compound indexes for common query patterns
purchaseSchema.index({ userid: 1, timestamp: -1 }); // Get user purchases sorted by date
purchaseSchema.index({ timestamp: -1 }); // Get recent purchases
purchaseSchema.index({ createdAt: -1 }); // For time-based queries

// Add a method to the schema
purchaseSchema.methods.toJSON = function() {
  const obj = this.toObject();
  obj.id = obj._id;
  delete obj._id;
  delete obj.__v;
  return obj;
};

// Static method for analytics
purchaseSchema.statics.getTotalRevenue = async function() {
  const result = await this.aggregate([
    {
      $group: {
        _id: null,
        total: { $sum: '$price' },
        count: { $sum: 1 }
      }
    }
  ]);
  return result[0] || { total: 0, count: 0 };
};

const Purchase = mongoose.model('Purchase', purchaseSchema);

module.exports = { Purchase };