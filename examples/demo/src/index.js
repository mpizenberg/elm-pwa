import { init } from "../../../js/src/index.js";

var topic = localStorage.getItem("pushTopic");
if (!topic) {
  topic = crypto.randomUUID();
  localStorage.setItem("pushTopic", topic);
}

var app = window.Elm.Main.init({
  node: document.getElementById("app"),
  flags: { isOnline: navigator.onLine, topic: topic, isStandalone: window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true },
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
