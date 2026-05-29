/* Shared review-page behavior: theme toggle (light/dark) via control-bar buttons.
   Event-delegated so it works on every styled review page without per-page wiring. */
(function () {
  var root = document.documentElement;
  if (!root.getAttribute('data-theme')) root.setAttribute('data-theme', 'light');

  function sync() {
    document.querySelectorAll('.controlbar button[data-set]').forEach(function (b) {
      b.classList.toggle('on', root.getAttribute('data-' + b.getAttribute('data-set')) === b.getAttribute('data-val'));
    });
    var t = document.getElementById('now-th');
    if (t) t.textContent = root.getAttribute('data-theme') || 'light';
  }

  document.addEventListener('click', function (e) {
    var b = e.target.closest ? e.target.closest('.controlbar button[data-set]') : null;
    if (b) {
      root.setAttribute('data-' + b.getAttribute('data-set'), b.getAttribute('data-val'));
      sync();
    }
  });

  sync();
})();
