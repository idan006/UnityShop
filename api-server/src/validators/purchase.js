// api-server/src/validators/purchase.js
const Joi = require('joi');

const createPurchaseSchema = Joi.object({
  username: Joi.string()
    .min(3)
    .max(50)
    .pattern(/^[a-zA-Z0-9_-]+$/)
    .required()
    .messages({
      'string.min': 'Username must be at least 3 characters long',
      'string.max': 'Username must not exceed 50 characters',
      'string.pattern.base': 'Username can only contain letters, numbers, underscores, and hyphens',
      'any.required': 'Username is required'
    }),
  
  userid: Joi.string()
    .pattern(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
    .required()
    .messages({
      'string.pattern.base': 'User ID must be a valid UUID',
      'any.required': 'User ID is required'
    }),
  
  price: Joi.number()
    .positive()
    .precision(2)
    .max(100000)
    .required()
    .messages({
      'number.positive': 'Price must be a positive number',
      'number.max': 'Price must not exceed 100,000',
      'any.required': 'Price is required'
    })
});

function validateCreatePurchase(req, res, next) {
  const { error, value } = createPurchaseSchema.validate(req.body, {
    abortEarly: false, // Return all errors, not just the first one
    stripUnknown: true // Remove unknown fields
  });
  
  if (error) {
    return res.status(400).json({
      error: 'Validation failed',
      details: error.details.map(detail => ({
        field: detail.path.join('.'),
        message: detail.message
      }))
    });
  }
  
  // Attach validated data to request
  req.validatedBody = value;
  next();
}

module.exports = { validateCreatePurchase };