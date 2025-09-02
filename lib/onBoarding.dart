import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnBoardingStep {
  final String selector;
  final String explanation;
  final int order;

  OnBoardingStep({
    required this.selector,
    required this.explanation,
    required this.order,
  });

  Map<String, dynamic> toMap() {
    return {
      'selector': selector,
      'explanation': explanation,
      'order': order,
    };
  }
}

class OnBoardingManager {
  static const String _onboardingKey = 'onboarding_completed_';

  final InAppWebViewController? webViewController;
  final List<OnBoardingStep> steps;
  final String onboardingId;
  final VoidCallback? onCompleted;

  int _currentStep = 0;
  bool _isActive = false;
  bool _isProcessing = false;
  Timer? _checkTimer;

  OnBoardingManager({
    required this.webViewController,
    required this.steps,
    required this.onboardingId,
    this.onCompleted,
  });

  Future<bool> _hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_onboardingKey$onboardingId') ?? false;
  }

  Future<void> _setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_onboardingKey$onboardingId', true);
  }

  Future<void> startOnboarding() async {
    if (_isActive || webViewController == null) return;

    bool completed = await _hasCompletedOnboarding();
    if (completed) return;

    _isActive = true;
    _currentStep = 0;

    await _injectOnboardingCSS();
    await _showCurrentStep();
  }

  Future<void> _injectOnboardingCSS() async {
    const String css = '''
.onboarding-highlight {
  border: 3px solid #ff4444 !important;
  border-radius: 8px !important;
  box-shadow: 0 0 0 4px rgba(255, 68, 68, 0.3) !important;
  position: relative !important;
  z-index: 9999 !important;
}

.onboarding-tooltip {
  position: absolute !important;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
  color: white !important;
  padding: 16px 20px !important;
  border-radius: 12px !important;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3) !important;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
  font-size: 14px !important;
  line-height: 1.5 !important;
  max-width: 280px !important;
  z-index: 10000 !important;
  animation: fadeInUp 0.3s ease-out !important;
  backdrop-filter: blur(10px) !important;
}

.onboarding-tooltip::before {
  content: '' !important;
  position: absolute !important;
  top: -8px !important;
  left: 20px !important;
  width: 0 !important;
  height: 0 !important;
  border-left: 8px solid transparent !important;
  border-right: 8px solid transparent !important;
  border-bottom: 8px solid #667eea !important;
}

.onboarding-tooltip.tooltip-above::before {
  top: auto !important;
  bottom: -8px !important;
  border-bottom: none !important;
  border-top: 8px solid #667eea !important;
}

.onboarding-step-number {
  display: inline-block !important;
  background: rgba(255, 255, 255, 0.2) !important;
  color: white !important;
  width: 24px !important;
  height: 24px !important;
  border-radius: 50% !important;
  text-align: center !important;
  line-height: 24px !important;
  font-weight: bold !important;
  font-size: 12px !important;
  margin-right: 8px !important;
  float: left !important;
}

.onboarding-text {
  margin-left: 32px !important;
  margin-top: 2px !important;
}

.onboarding-next-btn {
  background: rgba(255, 255, 255, 0.2) !important;
  border: 1px solid rgba(255, 255, 255, 0.3) !important;
  color: white !important;
  padding: 8px 16px !important;
  border-radius: 6px !important;
  font-size: 12px !important;
  cursor: pointer !important;
  margin-top: 12px !important;
  float: right !important;
  transition: all 0.2s ease !important;
}

.onboarding-next-btn:hover {
  background: rgba(255, 255, 255, 0.3) !important;
  transform: translateY(-1px) !important;
}

.swal2-container .onboarding-highlight {
  z-index: 10001 !important;
}

.swal2-container .onboarding-tooltip {
  z-index: 10002 !important;
}

@keyframes fadeInUp {
  from {
    opacity: 0 !important;
    transform: translateY(10px) !important;
  }
  to {
    opacity: 1 !important;
    transform: translateY(0) !important;
  }
}
''';
    await webViewController!.evaluateJavascript(source: '''
    if (!document.getElementById('onboarding-styles')) {
      const style = document.createElement('style');
      style.id = 'onboarding-styles';
      style.textContent = `$css`;
      document.head.appendChild(style);
    }
  ''');
  }

  Future<void> _showCurrentStep() async {
    if (_currentStep >= steps.length || webViewController == null) {
      await _completeOnboarding();
      return;
    }

    final step = steps[_currentStep];

    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(Duration(milliseconds: 300), (timer) async {
      try {
        final exists = await webViewController!.evaluateJavascript(source: '''
          (function() {
            const element = document.querySelector('${step.selector}');
            return element !== null && element.offsetParent !== null;
          })();
        ''');

        if (exists == true) {
          timer.cancel();
          await _highlightElement(step);
        }
      } catch (e) {
        // Continue checking
      }
    });
  }

  Future<void> _highlightElement(OnBoardingStep step) async {
    final jsCode = '''
  (function() {
    document.querySelectorAll('.onboarding-highlight').forEach(el => {
      el.classList.remove('onboarding-highlight');
    });
    document.querySelectorAll('.onboarding-tooltip').forEach(el => {
      el.remove();
    });
    
    let element = document.querySelector('${step.selector}');
    
    if (!element) {
      if ('${step.selector}'.includes('has(.w3-text-pink)')) {
        element = document.querySelector('label .w3-text-pink')?.closest('label');
      } else if ('${step.selector}'.includes('has(.w3-text-blue)')) {
        element = document.querySelector('label .w3-text-blue')?.closest('label');
      }
    }
    
    if (!element) return false;
    
    element.classList.add('onboarding-highlight');
    
    const tooltip = document.createElement('div');
    tooltip.className = 'onboarding-tooltip';
    tooltip.innerHTML = `
      <div class="onboarding-step-number">${step.order}</div>
      <div class="onboarding-text">${step.explanation}</div>
      <button class="onboarding-next-btn" id="onboarding-next-${step.order}">
        Next
      </button>
      <div style="clear: both;"></div>
    `;
    
    const rect = element.getBoundingClientRect();
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;
    
    tooltip.style.position = 'absolute';
    tooltip.style.top = (rect.bottom + scrollTop + 12) + 'px';
    tooltip.style.left = (rect.left + scrollLeft) + 'px';
    
    document.body.appendChild(tooltip);
    
    // Add click handler immediately after adding to DOM
    const nextBtn = document.getElementById('onboarding-next-${step.order}');
    if (nextBtn) {
      nextBtn.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('nextOnboardingStep');
      });
    }
    const tooltipRect = tooltip.getBoundingClientRect();
    
    if (tooltipRect.right > window.innerWidth) {
      tooltip.style.left = (window.innerWidth - tooltipRect.width - 20 + scrollLeft) + 'px';
    }
    
    if (tooltipRect.bottom > window.innerHeight) {
      tooltip.style.top = (rect.top + scrollTop - tooltipRect.height - 12) + 'px';
      tooltip.classList.add('tooltip-above');
    }
    
    element.scrollIntoView({ 
      behavior: 'smooth', 
      block: 'center',
      inline: 'center'
    });
    
    return true;
  })();
''';

    await webViewController!.evaluateJavascript(source: jsCode);
  }

  Future<void> nextStep() async {
    if (_isProcessing) return; // Prevent multiple rapid clicks

    _isProcessing = true;

    // Immediately remove current highlights and tooltips
    await _clearCurrentHighlights();
    _currentStep++;

    // Add delay to allow page transitions
    await Future.delayed(Duration(milliseconds: 200));
    await _showCurrentStep();

    _isProcessing = false;
  }

  Future<void> _clearCurrentHighlights() async {
    if (webViewController == null) return;

    try {
      await webViewController!.evaluateJavascript(source: '''
        document.querySelectorAll('.onboarding-highlight').forEach(el => {
          el.classList.remove('onboarding-highlight');
        });
        document.querySelectorAll('.onboarding-tooltip').forEach(el => {
          el.remove();
        });
      ''');
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _completeOnboarding() async {
    _isActive = false;
    _checkTimer?.cancel();

    await webViewController!.evaluateJavascript(source: '''
    document.querySelectorAll('.onboarding-highlight').forEach(el => {
      el.classList.remove('onboarding-highlight');
    });
    document.querySelectorAll('.onboarding-tooltip').forEach(el => {
      el.remove();
    });
  ''');

    await _setOnboardingCompleted();
    onCompleted?.call();
  }

  Future<void> skipOnboarding() async {
    await _completeOnboarding();
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_onboardingKey$onboardingId');
  }

  void dispose() {
    _checkTimer?.cancel();
  }
}
