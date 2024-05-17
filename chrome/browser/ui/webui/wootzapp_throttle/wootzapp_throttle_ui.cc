#include "chrome/browser/ui/webui/wootzapp_throttle/wootzapp_throttle_ui.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "base/base64.h"
#include "base/containers/to_value_list.h"
#include "base/containers/unique_ptr_adapters.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/i18n/time_formatting.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/types/expected.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/webui/webui_util.h"
#include "chrome/common/webui_url_constants.h"
#include "chrome/grit/wootzapp_throttle_resources.h"
#include "chrome/grit/wootzapp_throttle_resources_map.h"
#include "components/prefs/pref_member.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/browser/web_ui_message_handler.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "net/base/net_errors.h"
#include "net/base/network_isolation_key.h"
#include "net/base/schemeful_site.h"
#include "services/network/public/cpp/request_destination.h"
#include "services/network/public/mojom/clear_data_filter.mojom.h"
#include "services/network/public/mojom/network_context.mojom.h"
#include "ui/resources/grit/webui_resources.h"
#include "url/origin.h"
#include "url/scheme_host_port.h"

using content::BrowserThread;



namespace {
    void CreateAndAddWootzappThrottleHTMLSource(Profile* profile) {
        content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      profile, chrome::kChromeUIWootzappThrottleHost);
            webui::SetupWebUIDataSource(
            source,
            base::make_span(kWootzappThrottleResources, kWootzappThrottleResourcesSize),
            IDR_WOOTZAPP_THROTTLE_INDEX_HTML);
            webui::EnableTrustedTypesCSP(source);
   }

    class WootzappThrottleMessageHandler : public content::WebUIMessageHandler {
        public:
            explicit WootzappThrottleMessageHandler(content::WebUI* web_ui);

            WootzappThrottleMessageHandler(const WootzappThrottleMessageHandler&) = delete;
            WootzappThrottleMessageHandler& operator=(const WootzappThrottleMessageHandler&) = delete;

            ~WootzappThrottleMessageHandler() override = default;

            protected:
            // WebUIMessageHandler implementation:
            void RegisterMessages() override;
            void OnJavascriptDisallowed() override;

            private:
            network::mojom::NetworkContext* GetNetworkContext();
            const base::UnguessableToken devtools_token;

            void OnSetNetworkThrottling(const base::Value::List& list);

            raw_ptr<content::WebUI> web_ui_;
            base::WeakPtrFactory<WootzappThrottleMessageHandler> weak_factory_{this};
    };

    WootzappThrottleMessageHandler::WootzappThrottleMessageHandler(content::WebUI* web_ui)
        : web_ui_(web_ui) {}

    void WootzappThrottleMessageHandler::RegisterMessages() {
        web_ui_->RegisterMessageCallback(
            "setNetworkThrottling",
            base::BindRepeating(&WootzappThrottleMessageHandler::OnSetNetworkThrottling,
                                base::Unretained(this)));
    }

    void WootzappThrottleMessageHandler::OnJavascriptDisallowed() {
        weak_factory_.InvalidateWeakPtrs();
    }

    void WootzappThrottleMessageHandler::OnSetNetworkThrottling(
        const base::Value::List& args) {
        DCHECK(args.size() == 6) << "Expected 6 arguments for network throttling settings";

        bool offline = args[0].GetBool();
        double latency = args[1].GetDouble();
        double download_throughput = args[2].GetDouble();
        double upload_throughput = args[3].GetDouble();
        double packet_loss = args[4].GetDouble();
        int packet_queue_length = args[5].GetInt();

        network::mojom::NetworkConditionsPtr conditions = network::mojom::NetworkConditions::New();
        conditions->offline = offline;
        conditions->latency = base::Milliseconds(latency);
        conditions->download_throughput = download_throughput;
        conditions->upload_throughput = upload_throughput;
        conditions->packet_loss = packet_loss;
        conditions->packet_queue_length = packet_queue_length;

        GetNetworkContext()->SetNetworkConditions(devtools_token, std::move(conditions));
    }

    network::mojom::NetworkContext*
    WootzappThrottleMessageHandler::GetNetworkContext() {

    return web_ui_->GetWebContents()
      ->GetBrowserContext()
      ->GetDefaultStoragePartition()
      ->GetNetworkContext();
}

} // namespace


// WootzappThrottleUI

    WootzappThrottleUI::WootzappThrottleUI(content::WebUI* web_ui)
    : WebUIController(web_ui) {
    web_ui->AddMessageHandler(
      std::make_unique<WootzappThrottleMessageHandler>(web_ui));

        // Set up the chrome://net-internals/ source.
        CreateAndAddWootzappThrottleHTMLSource(Profile::FromWebUI(web_ui));
    }