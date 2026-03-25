function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

// BUG: division doesn't handle zero
// TODO: add input validation
function divide(a, b) {
  return a / b;
}

function multiply(a, b) {
  return a * b;
}

module.exports = { add, subtract, divide, multiply };
