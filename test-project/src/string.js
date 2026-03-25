// TODO: handle unicode properly
function capitalize(str) {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// TODO: add truncate function
// TODO: add slugify function

function reverse(str) {
  return str.split('').reverse().join('');
}

function wordCount(str) {
  if (!str || !str.trim()) return 0;
  return str.trim().split(/\s+/).length;
}

module.exports = { capitalize, reverse, wordCount };
