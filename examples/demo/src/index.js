import {
  init,
  isStandalone,
  iosInstallHint,
  /* defaultIsInAppBrowser, */
} from "../../../js/src/index.js";

var topic = localStorage.getItem("pushTopic");
if (!topic) {
  topic = crypto.randomUUID();
  localStorage.setItem("pushTopic", topic);
}

var app = window.Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    isOnline: navigator.onLine,
    topic: topic,
    isStandalone: isStandalone(),
    iosInstallHint: iosInstallHint(),
    // Example: extend the default in-app browser list with a custom one.
    // iosInstallHint: iosInstallHint({
    //   isInAppBrowser: (ua) =>
    //     defaultIsInAppBrowser(ua) || /MyCorpApp/i.test(ua),
    // }),
  },
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
