import { init } from "../../../js/src/index.js";

var topic = localStorage.getItem("pushTopic");
if (!topic) {
  topic = crypto.randomUUID();
  localStorage.setItem("pushTopic", topic);
}

var app = window.Elm.Main.init({
  node: document.getElementById("app"),
  flags: { isOnline: navigator.onLine, topic: topic },
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
