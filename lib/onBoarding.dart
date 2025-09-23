import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnBoardingStep {
  final String selector;
  final String explanation;
  final int order;
  final String? clickAction;

  OnBoardingStep({
    required this.selector,
    required this.explanation,
    required this.order,
    this.clickAction,
  });

  Map<String, dynamic> toMap() {
    return {
      'selector': selector,
      'explanation': explanation,
      'order': order,
      'clickAction': clickAction,
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
.onboarding-overlay {
  position: fixed !important;
  top: 0 !important;
  left: 0 !important;
  width: 100vw !important;
  height: 100vh !important;
  background: rgba(0, 0, 0, 0.7) !important;
  z-index: 9998 !important;
  pointer-events: auto !important;
}

.onboarding-highlight {
  position: relative !important;
  z-index: 9999 !important;
  pointer-events: auto !important;
}

.onboarding-highlight::before {
  content: '' !important;
  position: absolute !important;
  top: -8px !important;
  left: -8px !important;
  right: -8px !important;
  bottom: -8px !important;
  border: 2px solid rgba(255, 255, 255, 0.8) !important;
  border-radius: 8px !important;
  background: transparent !important;
  z-index: 10001 !important;
  pointer-events: none !important;
}

.onboarding-cutout {
  position: absolute !important;
  background: transparent !important;
  z-index: 10000 !important;
  pointer-events: none !important;
  box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.7) !important;
  border-radius: 12px !important;
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
  z-index: 10002 !important;
  animation: fadeInUp 0.3s ease-out !important;
  backdrop-filter: blur(10px) !important;
  pointer-events: auto !important;
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
  margin-bottom: 12px !important;
}

.onboarding-buttons {
  display: flex !important;
  justify-content: space-between !important;
  margin-top: 12px !important;
  width: 100% !important;
}

.onboarding-prev-btn, .onboarding-next-btn {
  background: rgba(255, 255, 255, 0.2) !important;
  border: 1px solid rgba(255, 255, 255, 0.3) !important;
  color: white !important;
  padding: 8px 16px !important;
  border-radius: 6px !important;
  font-size: 12px !important;
  cursor: pointer !important;
  transition: all 0.2s ease !important;
  min-width: 60px !important;
  text-align: center !important;
}

.onboarding-prev-btn:hover, .onboarding-next-btn:hover {
  background: rgba(255, 255, 255, 0.3) !important;
  transform: translateY(-1px) !important;
}

.onboarding-prev-btn:disabled {
  opacity: 0.5 !important;
  cursor: not-allowed !important;
  transform: none !important;
}

.swal2-container .onboarding-highlight {
  z-index: 10001 !important;
}

.swal2-container .onboarding-cutout {
  z-index: 10000 !important;
}

.swal2-container .onboarding-tooltip {
  z-index: 10003 !important;
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
      }
    });
  }

  Future<void> _highlightElement(OnBoardingStep step) async {
    final jsCode = '''
  (function() {
    document.querySelectorAll('.onboarding-cutout').forEach(el => el.remove());
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
    
    const rect = element.getBoundingClientRect();
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;
    
    const cutout = document.createElement('div');
    cutout.className = 'onboarding-cutout';
    cutout.style.position = 'absolute';
    cutout.style.top = (rect.top + scrollTop - 8) + 'px';
    cutout.style.left = (rect.left + scrollLeft - 8) + 'px';
    cutout.style.width = (rect.width + 16) + 'px';
    cutout.style.height = (rect.height + 16) + 'px';
    
    document.body.appendChild(cutout);
    
    const tooltip = document.createElement('div');
    tooltip.className = 'onboarding-tooltip';
    tooltip.innerHTML = `
      <div class="onboarding-step-number">${step.order}</div>
      <div class="onboarding-text">${step.explanation}</div>
      <div class="onboarding-buttons">
        <button class="onboarding-prev-btn" id="onboarding-prev-${step.order}" ${_currentStep == 0 ? 'disabled' : ''}>
          Prev
        </button>
        <button class="onboarding-next-btn" id="onboarding-next-${step.order}">
          Next
        </button>
      </div>
    `;
    
    tooltip.style.position = 'absolute';
    tooltip.style.top = (rect.bottom + scrollTop + 12) + 'px';
    tooltip.style.left = (rect.left + scrollLeft) + 'px';
    
    document.body.appendChild(tooltip);
    
    const prevBtn = document.getElementById('onboarding-prev-${step.order}');
    const nextBtn = document.getElementById('onboarding-next-${step.order}');
    
    if (prevBtn) {
      prevBtn.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('prevOnboardingStep');
      });
    }
    
    if (nextBtn) {
      nextBtn.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        ${step.clickAction != null ? step.clickAction! : 'window.flutter_inappwebview.callHandler(\'nextOnboardingStep\');'}
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
    if (_isProcessing) return;

    _isProcessing = true;
    await _clearCurrentHighlights();
    _currentStep++;
    await Future.delayed(Duration(milliseconds: 200));
    await _showCurrentStep();
    _isProcessing = false;
  }

  Future<void> prevStep() async {
    if (_isProcessing || _currentStep <= 0) return;

    _isProcessing = true;
    await _clearCurrentHighlights();
    _currentStep--;
    await Future.delayed(Duration(milliseconds: 200));
    await _showCurrentStep();
    _isProcessing = false;
  }

  Future<void> _clearCurrentHighlights() async {
    if (webViewController == null) return;

    try {
      await webViewController!.evaluateJavascript(source: '''
        document.querySelectorAll('.onboarding-cutout').forEach(el => el.remove());
        document.querySelectorAll('.onboarding-highlight').forEach(el => {
          el.classList.remove('onboarding-highlight');
        });
        document.querySelectorAll('.onboarding-tooltip').forEach(el => {
          el.remove();
        });
      ''');
    } catch (e) {
    }
  }

  Future<void> _completeOnboarding() async {
    _isActive = false;
    _checkTimer?.cancel();

    await webViewController!.evaluateJavascript(source: '''
    document.querySelectorAll('.onboarding-cutout').forEach(el => el.remove());
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

  static List<OnBoardingStep> getDefaultOnboardingSteps() {
    return [
      OnBoardingStep(
        selector: '.w-100.text-center h6',
        explanation: 'This is where the location shows that you need to pick up',
        order: 1,
      ),
      OnBoardingStep(
        selector: '.w3-border.w3-padding.w3-large.w3-round.w3-blue.text-center',
        explanation: 'This is where the Section Name is showing',
        order: 2,
      ),
      OnBoardingStep(
        selector: '#pindot',
        explanation: 'Click this to proceed with handling the current item in this section',
        order: 3,
        clickAction: "document.querySelector('#pindot').click(); window.flutter_inappwebview.callHandler('nextOnboardingStep');",
      ),
      OnBoardingStep(
        selector: '.swal2-content .w3-border.w3-padding.w3-xxxlarge.w3-round.w3-blue',
        explanation: 'It will show again the section of where to get the item',
        order: 4,
        clickAction: "document.querySelector('.swal2-confirm.w3-btn.w3-indigo.w3-xlarge').click(); window.flutter_inappwebview.callHandler('nextOnboardingStep');",
      ),
      OnBoardingStep(
        selector: 'label:has(.w3-text-pink)',
        explanation: 'It will show here the Priority Tag and it can be click to see the drawing of it',
        order: 5,
      ),
    ];
  }

  void dispose() {
    _checkTimer?.cancel();
  }
}