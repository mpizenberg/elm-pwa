import { init } from "../../../js/src/index.js";

var app = window.Elm.Main.init({
  node: document.getElementById("app"),
  flags: navigator.onLine,
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
