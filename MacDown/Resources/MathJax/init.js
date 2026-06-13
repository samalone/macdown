(function () {

MathJax.Hub.Config({
	'showProcessingMessages': false,
	'messageStyle': 'none'
});

// Tell the (WKWebView) host when the initial typeset is done, so it can run
// its load-completion handling (zoom, scroll-sync) against the final layout.
MathJax.Hub.Register.StartupHook('End', function () {
	if (window.webkit && window.webkit.messageHandlers
			&& window.webkit.messageHandlers.mathJaxEnd) {
		window.webkit.messageHandlers.mathJaxEnd.postMessage(1);
	}
});

})();
