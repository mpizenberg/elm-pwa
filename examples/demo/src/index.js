import {
  init,
  evaluateInstallHint,
  /* defaultIsInAppBrowser, */
} from "../../../js/src/index.js";

var topic = localStorage.getItem("pushTopic");
if (!topic) {
  topic = crypto.randomUUID();
  localStorage.setItem("pushTopic", topic);
}

// Keep these options identical to the ones passed to `init` below so the
// initial flag and the runtime `installHintChanged` events agree.
var installHintOptions = {
  // Hardens against chrome-less in-app WebViews (Discord, Slack, ...) that
  // can fake a standalone display mode. The manifest's start_url adds this
  // param, so only real PWA launches see it.
  requireStartUrlParam: "source",
  // Example: extend the default in-app browser list with a custom one.
  // isInAppBrowser: (ua) =>
  //   defaultIsInAppBrowser(ua) || /MyCorpApp/i.test(ua),
};

var app = window.Elm.Main.init({
  node: document.getElementById("app"),
  flags: {
    isOnline: navigator.onLine,
    topic: topic,
    installHint: evaluateInstallHint(installHintOptions),
  },
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
  ...installHintOptions,
});
