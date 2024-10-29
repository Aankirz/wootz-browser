package com.wootz.browser.impl;

import org.chromium.android_webview.AwConsoleMessage;
import org.chromium.android_webview.AwContentsClient;
import org.chromium.android_webview.AwContentsClientBridge.ClientCertificateRequestCallback;
import org.chromium.android_webview.AwHttpAuthHandler;
import org.chromium.android_webview.InterceptedRequestData;
import org.chromium.android_webview.JsPromptResultReceiver;
import org.chromium.android_webview.JsResultReceiver;
import org.chromium.android_webview.AwRenderProcess;
import org.chromium.android_webview.AwRenderProcessGoneDetail;
import org.chromium.android_webview.permission.AwPermissionRequest;
import org.chromium.android_webview.AwGeolocationPermissions;
import org.chromium.android_webview.safe_browsing.AwSafeBrowsingResponse;
import org.chromium.android_webview.SafeBrowsingAction;
import org.chromium.base.Callback;
import org.chromium.components.embedder_support.util.WebResourceResponseInfo;

import com.wootz.browser.WootzJsResult;
import com.wootz.browser.WootzView;
import com.wootz.browser.WootzViewClient;
import com.wootz.browser.WootzWebClient;
import android.annotation.TargetApi;
import android.graphics.Bitmap;
import android.graphics.Picture;
import android.net.http.SslError;
import android.os.Build;
import android.os.Message;
import android.util.Log; 
import android.view.KeyEvent;
import android.view.View;
import android.webkit.ConsoleMessage;
import android.webkit.DownloadListener;
import android.widget.Toast;
import android.webkit.ValueCallback;
import android.webkit.WebResourceResponse;
import android.webkit.WebChromeClient.CustomViewCallback;
import android.webkit.WebView.FindListener;
import android.webkit.WebChromeClient;
import java.security.Principal;

/** Glue that passes calls from the Chromium view to a WebWootzClient. */
public class WootzAwContentsClientProxy extends AwContentsClient {
  // Inspired from
  //     chromium/src/android_webview/test/shell/src/org/chromium/android_webview/test/NullContentsClient:w
  
  //     chromium/src/android_webview/javatests/src/org/chromium/android_webview/tests/*ContentsClient
  //     http://developer.android.com/reference/android/webkit/WebWootzClient.html

  /** The view whose clients are proxied by this instance. */
  private final WootzView view_;

  /** WootzView equivalent of WebViewClient. */
  private WootzViewClient viewClient_;

  /** WootzView equivalent of WebWootzClient. */
  private WootzWebClient webClient_;

  /** Receives download notifications. */
  private DownloadListener downloadListener_;

  /** Receives find results notifications. */
  private FindListener findListener_;


  /** Resets the WootzViewClient proxy target. */
  public void setWootzViewClient(WootzViewClient WootzViewClient) {
    viewClient_ = WootzViewClient;
  }

  /** Resets the WootzWebClient proxy target. */
  public void setWootzWebClient(WootzWebClient WootzWebClient) {
    webClient_ = WootzWebClient;
  }

  @Override
  public void onReceivedHttpError(AwWebResourceRequest request, WebResourceResponseInfo response) {
    Log.e("WootzViewClient", "HTTP error received for URL");
  }

  @Override
  public void onPermissionRequestCanceled(AwPermissionRequest awPermissionRequest) {
      // Log the event
      Log.i("WootzAwContentsClientProxy", "Permission request canceled for: " + awPermissionRequest.getOrigin());
  
      // Custom handling, for example, showing a message to the user
      if (view_ != null) {
          view_.post(new Runnable() {
              @Override
              public void run() {
                  Toast.makeText(view_.getContext(), "Permission request canceled: " + awPermissionRequest.getOrigin(), Toast.LENGTH_LONG).show();
              }
          });
      }
  
      // Additional custom handling logic can be added here, e.g., reset UI elements or take further actions
  }  

  @Override
  public void onPermissionRequest(AwPermissionRequest awPermissionRequest) {
      // Example: Grant all permissions
      awPermissionRequest.grant();
  }

  @Override
  public void onSafeBrowsingHit(AwWebResourceRequest request, int threatType, org.chromium.base.Callback<AwSafeBrowsingResponse> callback) {
      // Create a new response indicating that the user should proceed and enable reporting
          // Example of creating a Safe Browsing response
      AwSafeBrowsingResponse response = new AwSafeBrowsingResponse(
            SafeBrowsingAction.SHOW_INTERSTITIAL,  // This is the action taken, for example proceeding with page load
   true             // Enable reporting of the Safe Browsing hit
      );

  
      // Provide the response to the callback
      callback.onResult(response);
  }
  
  
  
  /** Resets the DownloadListener proxy target. */
  public void setDownloadListener(DownloadListener downloadListener) {
    downloadListener_ = downloadListener;
  }

  /** Resets the FindListener proxy target. */
  public void setFindListener(FindListener findListener) {
    findListener_ = findListener;
  }

  /**
   * Creates a new proxy.
   *
   * @param WootzView The view whose clients are proxied by this instance.
   */
  public WootzAwContentsClientProxy(WootzView WootzView) {
    view_ = WootzView;
    viewClient_ = null;
    webClient_ = null;
  }

  @Override
  public boolean onRenderProcessGone(AwRenderProcessGoneDetail detail) {
        if (detail.didCrash()) {
            // Handle the renderer crash
            return false; // Return false to destroy the WebView
        } else {
            // Handle the case where the renderer was killed by the system without crashing
            return true; // Return true to attempt recovery
        }
  }

  @Override
  public void onHideCustomView() {
    // TODO Auto-generated method stub
  }

  @Override
  public Bitmap getDefaultVideoPoster() {
    // TODO Auto-generated method stub
    return null;
  }

  //// WebWootzClient inexact proxies.
  @Override
  protected void handleJsAlert(String url, String message,
      JsResultReceiver receiver) {
    if (webClient_ != null) {
      WootzJsResult result = new WootzJsResult(
          new WootzJsResultReceiverProxy(receiver));
      if (webClient_.onJsAlert(view_, url, message, result)) {
        return;  // Alert will be handled by the client.
      }
    }
    receiver.cancel();  // Default alert handling.
  }
  @Override
  protected void handleJsBeforeUnload(String url, String message,
      JsResultReceiver receiver) {
    if (webClient_ != null) {
      WootzJsResult result = new WootzJsResult(
          new WootzJsResultReceiverProxy(receiver));
      if (webClient_.onJsBeforeUnload(view_, url, message,
          result)) {
        return;  // Alert will be handled by the client.
      }
    }
    receiver.cancel();  // Default alert handling.
  }
  @Override
  protected void handleJsConfirm(String url, String message,
      JsResultReceiver receiver) {
    if (webClient_ != null) {
      WootzJsResult result = new WootzJsResult(
          new WootzJsResultReceiverProxy(receiver));
      if (webClient_.onJsAlert(view_, url, message, result)) {
        return;  // Alert will be handled by the client.
      }
    }
    receiver.cancel();  // Default alert handling.
  }
  @Override
  protected void handleJsPrompt(String url, String message,
      String defaultValue, JsPromptResultReceiver receiver) {
    if (webClient_ != null) {
      WootzJsResult result = new WootzJsResult(
          new WootzJsPromptResultProxy(receiver));
      if (webClient_.onJsAlert(view_, url, message, result)) {
        return;  // Alert will be handled by the client.
      }
    }
    receiver.cancel();  // Default alert handling.
  }

  //// WebWootzClient proxy methods.
  @Override
  public void onProgressChanged(int progress) {
    if (webClient_ != null)
      webClient_.onProgressChanged(view_, progress);
  }
  @Override
  public void onReceivedIcon(Bitmap bitmap) {
    if (webClient_ != null)
      webClient_.onReceivedIcon(view_, bitmap);
  }
  @Override
  public void onReceivedTouchIconUrl(String url, boolean precomposed) {
    if (webClient_ != null)
      webClient_.onReceivedTouchIconUrl(view_, url, precomposed);
  }
  @Override
  public void onShowCustomView(View view, AwContentsClient.CustomViewCallback callback) {
      if (webClient_ != null) {
          // Convert AwContentsClient.CustomViewCallback to WebChromeClient.CustomViewCallback
          WebChromeClient.CustomViewCallback webChromeCallback = new WebChromeClient.CustomViewCallback() {
              @Override
              public void onCustomViewHidden() {
                  // Delegate to the AwContentsClient's callback
                  callback.onCustomViewHidden();
              }
          };
          
          // Pass the custom view and the callback to the web client
          webClient_.onShowCustomView(view, webChromeCallback);
      }
  }
  
  public void super_scrollTo(int x, int y) {
    view_.scrollTo(x, y);
  }
  @Override
  public void onRendererUnresponsive(AwRenderProcess renderProcess) {
    // Handle when the renderer becomes unresponsive
    // You can implement logic like notifying the user or attempting recovery.
  }

  @Override
  protected boolean onCreateWindow(boolean isDialog, boolean isUserGesture) {
    if (webClient_ != null) {
      // TODO(pwnall): figure out what to do here
      Message resultMsg = new Message();
      resultMsg.setTarget(null);
      resultMsg.obj = null; // WebView.WebViewTransport
      return webClient_.onCreateWindow(view_, isDialog,
          isUserGesture, resultMsg);
    } else {
      return false;
    }
  }
  @Override
  protected void onRequestFocus() {
    if (webClient_ != null)
      webClient_.onRequestFocus(view_);
  }
  @Override
  protected void onCloseWindow() {
    if (webClient_ != null)
      webClient_.onCloseWindow(view_);
  }

  @Override
  public void onGeolocationPermissionsShowPrompt(String origin, AwGeolocationPermissions.Callback callback) {
      if (webClient_ != null) {
          webClient_.onGeolocationPermissionsShowPrompt(origin, new android.webkit.GeolocationPermissions.Callback() {
              @Override
              public void invoke(String origin, boolean allow, boolean retain) {
                  // Pass the values from AwGeolocationPermissions.Callback to android.webkit.GeolocationPermissions.Callback
                  callback.invoke(origin, allow, retain);
              }
          });
      } else {
          // Handle the case where the callback is directly invoked
          callback.invoke(origin, true, false); // Grant geolocation permissions
      }
  }
  

  @Override
  public void showFileChooser(Callback<String[]> uploadFilePathsCallback, FileChooserParamsImpl fileChooserParams) {
      // You can handle the file chooser request here.
      // For example, to simulate a file selection you can directly call the callback:
      
      String[] fakeFilePaths = new String[]{"file:///fake/path/image.jpg"}; // Replace with actual file handling logic
      uploadFilePathsCallback.onResult(fakeFilePaths);
  
      // You can also implement more complex logic to open a real file chooser.
  }
  @Override
  public void onReceivedClientCertRequest(
      ClientCertificateRequestCallback callback, 
      String[] keyTypes, 
      Principal[] principals, 
      String host, 
      int port) {
      
      // Handle the client certificate request here.
      // For now, rejecting the request:
      callback.cancel();
      
      // If you want to accept, you would instead call:
      // callback.proceed(privateKey, certificateChain);
  }
  
  @Override
  public void onGeolocationPermissionsHidePrompt() {
    if (webClient_ != null)
      webClient_.onGeolocationPermissionsHidePrompt();
  }
  public boolean onConsoleMessage(AwConsoleMessage consoleMessage) {
    if (webClient_ != null) {
      return webClient_.onConsoleMessage(consoleMessage);
    } else {
      return false;
    }
  }
  @Override
  protected View getVideoLoadingProgressView() {
    if (webClient_ != null) {
      return webClient_.getVideoLoadingProgressView();
    } else {
      return null;
    }
  }
  public void getVisitedHistory(ValueCallback<String[]> callback) {
    if (webClient_ != null) {
      webClient_.getVisitedHistory(callback);
    } else {
      callback.onReceiveValue(new String[] {});
    }
  }
  @Override
  public void onReceivedTitle(String title) {
    if (viewClient_ != null) {
      webClient_.onReceivedTitle(view_, title);
    }
  }

  //// WebViewClient proxy methods.
  @Override
  public void onPageStarted(String url) {
    if (viewClient_ != null)
      viewClient_.onPageStarted(view_, url, null);
  }
  @Override
  public void onPageFinished(String url) {
    if (viewClient_ != null)
      viewClient_.onPageFinished(view_, url);
  }
  @Override
  public void onLoadResource(String url) {
    if (viewClient_ != null)
      viewClient_.onLoadResource(view_, url);
  }
  @Override
  public WebResourceResponseInfo shouldInterceptRequest(AwWebResourceRequest request) {
      if (viewClient_ != null) {
          WebResourceResponse response = viewClient_.shouldInterceptRequest(view_, request.url.toString());
          if (response != null) {
              // Convert WebResourceResponse to WebResourceResponseInfo
              return new WebResourceResponseInfo(
                  response.getMimeType(),
                  response.getEncoding(),
                  response.getData()
              );
          }
      }
      return null; // Return null to allow the request to proceed normally
  }  
  @Override
  public boolean hasWebViewClient() {
      // Check if the WootzViewClient (equivalent of WebViewClient) is set
      return viewClient_ != null;
  }
  @Override
  public void getVisitedHistory(Callback<String[]> callback) {
      if (webClient_ != null) {
          // Delegate the call to the WootzWebClient's getVisitedHistory method
          webClient_.getVisitedHistory(new ValueCallback<String[]>() {
              @Override
              public void onReceiveValue(String[] value) {
                  // Pass the visited history result to the provided callback
                  callback.onResult(value);
              }
          });
      } else {
          // If the webClient_ is not set, return an empty history
          callback.onResult(new String[] {});
      }
  }
  
  @Override
  public void onReceivedError(AwWebResourceRequest request, AwWebResourceError error) {
    if (viewClient_ != null) {
        viewClient_.onReceivedError(view_, error.errorCode, error.description, request.url);
    }
  }
  
  @Override
  public void onPageCommitVisible(String url) {
      if (viewClient_ != null) {
          viewClient_.onPageCommitVisible(view_, url);
      }
  }
  

  @Override
  public void onFormResubmission(Message dontResend, Message resend) {
    if (viewClient_ != null) {
      viewClient_.onFormResubmission(view_, dontResend, resend);
    } else {
      dontResend.sendToTarget();
    }
  }
  @Override
  public void doUpdateVisitedHistory(String url, boolean isReload) {
     if (viewClient_ != null)
       viewClient_.doUpdateVisitedHistory(view_, url, isReload);
  }
  @Override
  public void onReceivedSslError(Callback<Boolean> callback, SslError error) {
      if (viewClient_ != null) {
          // Use a lambda to convert Callback to ValueCallback
          ValueCallback<Boolean> valueCallback = result -> callback.onResult(result);
          WootzSslErrorHandlerProxy handler = new WootzSslErrorHandlerProxy(valueCallback);
          viewClient_.onReceivedSslError(view_, handler, error);
      } else {
          // If viewClient_ is not set, reject the SSL error by passing `false`
          callback.onResult(false);
      }
  }
  

  @Override
  public boolean shouldOverrideUrlLoading(AwWebResourceRequest request) {
      // If viewClient_ is available, delegate the URL handling to it
      if (viewClient_ != null) {
          return viewClient_.shouldOverrideUrlLoading(view_, request.url.toString());
      }
      
      // If not handled, return false to allow default behavior
      return false;
  }
  
  @Override
  public void onReceivedHttpAuthRequest(AwHttpAuthHandler handler,
      String host, String realm) {
    if (viewClient_ != null) {
      WootzHttpAuthHandlerProxy httpAuthHandler =
          new WootzHttpAuthHandlerProxy(handler);
      viewClient_.onReceivedHttpAuthRequest(view_, httpAuthHandler,
          host, realm);
    } else {
      handler.cancel();
    }
  }
  @Override
  public void onUnhandledKeyEvent(KeyEvent event) {
    if (viewClient_ != null)
      viewClient_.onUnhandledKeyEvent(view_, event);
  }

  @Override
  public void onRendererResponsive(AwRenderProcess renderProcess) {
      // Handle when the renderer becomes responsive again
      // For now, you can leave it empty or add some custom logic based on your requirements
  }  

  @Override
  public void onScaleChangedScaled(float oldScale, float newScale) {
    if (viewClient_ != null)
      viewClient_.onScaleChanged(view_, oldScale, newScale);
  }
  @Override
  public void onReceivedLoginRequest(String realm, String account,
      String args) {
    if (viewClient_ != null) {
      viewClient_.onReceivedLoginRequest(view_, realm, account,
          args);
    }
  }
  @Override
  public boolean shouldOverrideKeyEvent(KeyEvent event) {
    if (viewClient_ != null) {
      return viewClient_.shouldOverrideKeyEvent(view_, event);
    } else {
      return false;
    }
  }
  public boolean shouldOverrideUrlLoading(String url) {
    if (viewClient_ != null) {
      return viewClient_.shouldOverrideUrlLoading(view_, url);
    } else {
      return false;
    }
  }

  // DownloadListener proxy methods.
  @Override
  public void onDownloadStart(String url, String userAgent,
      String contentDisposition, String mimeType, long contentLength) {
    if (downloadListener_ != null) {
      downloadListener_.onDownloadStart(url, userAgent, contentDisposition,
          mimeType, contentLength);
    }
  }

  // FindListener proxy methods.
  @TargetApi(Build.VERSION_CODES.JELLY_BEAN)
  @Override
  public void onFindResultReceived(int activeMatchOrdinal,
      int numberOfMatches, boolean isDoneCounting) {
    if (findListener_ != null) {
      findListener_.onFindResultReceived(activeMatchOrdinal, numberOfMatches,
          isDoneCounting);
    }
  }

  // PictureListener is deprecated, so we don't proxy it.
  @Override
  public void onNewPicture(Picture picture) {
    return;
  }

}
