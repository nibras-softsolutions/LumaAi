// Vercel Speed Insights initialization
// This script injects the Vercel Speed Insights tracking

(function() {
  'use strict';
  
  // Initialize the queue
  window.si = window.si || function() {
    (window.siq = window.siq || []).push(arguments);
  };
  
  // Determine the script source
  function getScriptSrc() {
    // In development, use debug version
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
      return 'https://va.vercel-scripts.com/v1/speed-insights/script.debug.js';
    }
    // In production on Vercel, use the default path
    return '/_vercel/speed-insights/script.js';
  }
  
  // Inject the Speed Insights script
  function injectSpeedInsights() {
    const src = getScriptSrc();
    
    // Check if script is already loaded
    if (document.head.querySelector(`script[src*="${src}"]`)) {
      return;
    }
    
    const script = document.createElement('script');
    script.src = src;
    script.defer = true;
    script.dataset.sdkn = '@vercel/speed-insights';
    script.dataset.sdkv = '1.3.1';
    
    script.onerror = function() {
      console.log(
        '[Vercel Speed Insights] Failed to load script from ' + src + 
        '. Please check if any content blockers are enabled and try again.'
      );
    };
    
    document.head.appendChild(script);
  }
  
  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectSpeedInsights);
  } else {
    injectSpeedInsights();
  }
})();
