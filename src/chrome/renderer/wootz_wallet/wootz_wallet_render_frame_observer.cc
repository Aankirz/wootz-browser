/* Copyright (c) 2021 The Wootz Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "chrome/renderer/wootz_wallet/wootz_wallet_render_frame_observer.h"

#include <memory>
#include <optional>
#include <utility>
#include "base/logging.h"
#include "components/wootz_wallet/renderer/v8_helper.h"
#include "build/buildflag.h"
#include "content/public/common/isolated_world_ids.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/web/blink.h"
#include "third_party/blink/public/web/web_local_frame.h"

namespace wootz_wallet {

WootzWalletRenderFrameObserver::WootzWalletRenderFrameObserver(
    content::RenderFrame* render_frame)
    : RenderFrameObserver(render_frame) {
      LOG(ERROR)<<"WootzWalletRenderFrameObserver ANKIT";
    }

WootzWalletRenderFrameObserver::~WootzWalletRenderFrameObserver() = default;

void WootzWalletRenderFrameObserver::DidStartNavigation(
    const GURL& url,
    std::optional<blink::WebNavigationType> navigation_type) {
  url_ = url;
}

bool WootzWalletRenderFrameObserver::IsPageValid() {
  // There could be empty, invalid and "about:blank" URLs,
  // they should fallback to the main frame rules
  if (url_.is_empty() || !url_.is_valid() || url_.spec() == "about:blank") {
    url_ = url::Origin(render_frame()->GetWebFrame()->GetSecurityOrigin())
               .GetURL();
  }
  return url_.SchemeIsHTTPOrHTTPS();
}

bool WootzWalletRenderFrameObserver::CanCreateProvider() {
  if (!IsPageValid()) {
    return false;
  }

  // Wallet provider objects should only be created in secure contexts
  if (!render_frame()->GetWebFrame()->GetDocument().IsSecureContext()) {
    return false;
  }

  // Scripts can't be executed on provisional frames
  if (render_frame()->GetWebFrame()->IsProvisional()) {
    return false;
  }

  return true;
}

void WootzWalletRenderFrameObserver::DidFinishLoad() {
#if !BUILDFLAG(IS_ANDROID)
  // Only record P3A for desktop and valid HTTP/HTTPS pages
  if (!IsPageValid()) {
    return;
  }


  p3a_util_.ReportJSProviders(render_frame());
#endif
}

void WootzWalletRenderFrameObserver::DidClearWindowObject() {
  LOG(ERROR)<<"DidClearWindowObject ANKIT";
  if (!CanCreateProvider()) {
    return;
  }

  LOG(ERROR)<<"DidClearWindowObject2 ANKIT2";

  CHECK(render_frame());
  v8::Isolate* isolate =
      render_frame()->GetWebFrame()->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handle_scope(isolate);
  auto* web_frame = render_frame()->GetWebFrame();
  v8::Local<v8::Context> context = web_frame->MainWorldScriptContext();
  if (context.IsEmpty()) {
    return;
  }
  LOG(ERROR)<<"DidClearWindowObject3 ANKIT3";

  v8::MicrotasksScope microtasks(isolate, context->GetMicrotaskQueue(),
                                 v8::MicrotasksScope::kDoNotRunMicrotasks);





  if (
      web_frame->GetDocument().IsDOMFeaturePolicyEnabled(isolate, context,
                                                         "ethereum")) {
     LOG(ERROR)<<"JSEthereumProvider INSTALL ANKIT";                                                     
    JSEthereumProvider::Install(
true,
        true,
        render_frame());
  }

  if (web_frame->GetDocument().IsDOMFeaturePolicyEnabled(isolate, context,
                                                         "solana")
      ) {
    JSSolanaProvider::Install(
        true, render_frame());
  }
}

void WootzWalletRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace wootz_wallet
