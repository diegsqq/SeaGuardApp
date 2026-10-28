module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  extends: ['eslint:recommended', 'google'],
  rules: {
    'require-jsdoc': 'off',
    'max-len': 'off',
    'object-curly-spacing': 'off',
    'no-unused-vars': 'off',
    'quotes': 'off',
  },
};
