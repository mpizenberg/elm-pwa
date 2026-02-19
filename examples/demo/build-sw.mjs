import { generateSW } from "../../js/src/build.js";
import { writeFileSync } from "node:fs";

writeFileSync(
  "static/sw.js",
  generateSW({
    cacheName: "elm-pwa-v2",
    precacheUrls: [
      "/",
      "/elm.js",
      "/main.js",
      "/style.css",
      "/manifest.webmanifest",
    ],
  }),
);
