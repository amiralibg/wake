// Settings ▸ Appearance ▸ Site styles: the CSS you wrote for this site.
// params.styles is [{ site, css }]; a site covers its subdomains. Adopted style
// sheets aren't blocked by a page's Content-Security-Policy the way an inline
// <style> can be. window.__wakeStyles.apply(list) updates a page in place.
if (!window.__wakeStyles) {
  let sheet = null;
  const matches = (site) => location.hostname === site || location.hostname.endsWith('.' + site);
  window.__wakeStyles = {
    apply(list) {
      const css = (list || []).filter((style) => matches(style.site)).map((style) => style.css).join('\n');
      if (!sheet) {
        if (!css) return;
        sheet = new CSSStyleSheet();
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
      }
      sheet.replaceSync(css);
    },
  };
}
window.__wakeStyles.apply(params.styles);
