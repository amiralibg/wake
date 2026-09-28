// The page's icon: the 32 px one if it declares sizes, else any icon, else /favicon.ico.
const link = document.querySelector("link[rel~='icon'][sizes='32x32'], link[rel~='icon'], link[rel='apple-touch-icon']");
return link ? link.href : new URL('/favicon.ico', location.href).href;
