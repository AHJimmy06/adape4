/* Payment fields are hosted by Stripe, never handled by the application. */
(() => {
  const entries = new Map();
  let loading;
  function loadStripe() {
    if (window.Stripe) return Promise.resolve();
    if (!loading) loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://js.stripe.com/v3/';
      script.onload = resolve;
      script.onerror = () => reject(new Error('stripe_unavailable'));
      document.head.appendChild(script);
    }).catch(error => { loading = null; throw error; });
    return loading;
  }
  window.aerotechStripe = {
    async mount(id, key, secret, complete, error) {
      const state = { cancelled: false, checkout: null, observer: null };
      entries.set(id, state);
      try {
        await loadStripe();
        if (state.cancelled) return;
        if (!key.startsWith('pk_test_')) throw new Error('test_mode_required');
        const checkout = await window.Stripe(key).initEmbeddedCheckout({
          fetchClientSecret: async () => secret,
          onComplete: () => { if (!state.cancelled) complete(); },
        });
        if (state.cancelled) { checkout.destroy(); return; }
        state.checkout = checkout;
        const attach = () => {
          const host = document.getElementById(id);
          if (!host || state.cancelled) return;
          state.observer?.disconnect();
          checkout.mount(host);
        };
        if (document.getElementById(id)) attach();
        else {
          state.observer = new MutationObserver(attach);
          state.observer.observe(document.body, {childList:true, subtree:true});
        }
      } catch (_) { if (!state.cancelled) error('stripe_unavailable'); }
    },
    destroy(id) {
      const state = entries.get(id);
      if (!state) return;
      state.cancelled = true;
      state.observer?.disconnect();
      state.checkout?.destroy();
      entries.delete(id);
    },
  };
})();
