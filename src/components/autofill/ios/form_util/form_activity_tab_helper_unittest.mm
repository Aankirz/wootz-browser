// Copyright 2018 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "components/autofill/ios/form_util/form_activity_tab_helper.h"

#import <optional>

#import "base/strings/sys_string_conversions.h"
#import "base/test/ios/wait_util.h"
#import "base/test/metrics/histogram_tester.h"
#import "base/time/time.h"
#import "components/autofill/ios/form_util/autofill_test_with_web_state.h"
#import "components/autofill/ios/form_util/form_activity_observer.h"
#import "components/autofill/ios/form_util/form_handlers_java_script_feature.h"
#import "components/autofill/ios/form_util/form_util_java_script_feature.h"
#import "components/autofill/ios/form_util/test_form_activity_observer.h"
#import "ios/web/public/js_messaging/web_frame.h"
#import "ios/web/public/js_messaging/web_frames_manager.h"
#import "ios/web/public/test/fakes/fake_web_client.h"
#import "ios/web/public/test/fakes/fake_web_state_observer_util.h"
#import "ios/web/public/test/js_test_util.h"
#import "ios/web/public/test/web_test_with_web_state.h"

using autofill::FieldRendererId;
using autofill::FormActivityParams;
using autofill::FormRemovalParams;
using autofill::FormRendererId;
using autofill::test::kTrackFormMutationsDelayInMs;
using base::test::ios::kWaitForJSCompletionTimeout;
using base::test::ios::WaitUntilConditionOrTimeout;
using ::testing::ElementsAre;
using ::testing::IsEmpty;
using ::testing::Not;
using ::testing::StrEq;
using ::testing::UnorderedElementsAre;
using web::WebFrame;

// Tests fixture for autofill::FormActivityTabHelper class.
class FormActivityTabHelperTest : public AutofillTestWithWebState {
 public:
  FormActivityTabHelperTest()
      : AutofillTestWithWebState(std::make_unique<web::FakeWebClient>()) {
    web::FakeWebClient* web_client =
        static_cast<web::FakeWebClient*>(GetWebClient());
    web_client->SetJavaScriptFeatures(
        {autofill::FormUtilJavaScriptFeature::GetInstance(),
         autofill::FormHandlersJavaScriptFeature::GetInstance()});
  }

  void SetUp() override {
    web::WebTestWithWebState::SetUp();

    autofill::FormActivityTabHelper* tab_helper =
        autofill::FormActivityTabHelper::GetOrCreateForWebState(web_state());
    observer_ =
        std::make_unique<autofill::TestFormActivityObserver>(web_state());
    tab_helper->AddObserver(observer_.get());
  }

  void TearDown() override {
    autofill::FormActivityTabHelper* tab_helper =
        autofill::FormActivityTabHelper::GetOrCreateForWebState(web_state());
    tab_helper->RemoveObserver(observer_.get());
    web::WebTestWithWebState::TearDown();
  }

 protected:
  WebFrame* WaitForMainFrame() {
    __block WebFrame* main_frame = nullptr;
    EXPECT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool {
      web::WebFramesManager* frames_manager =
          autofill::FormUtilJavaScriptFeature::GetInstance()
              ->GetWebFramesManager(web_state());
      main_frame = frames_manager->GetMainWebFrame();
      return main_frame != nullptr;
    }));
    return main_frame;
  }

  // Verifies the form activity params received after a form mutation.
  void ValidateParamsAfterFormChangedEvent(const FormActivityParams& params) {
    FormActivityParams expected_activity_params;
    expected_activity_params.frame_id = WaitForMainFrame()->GetFrameId();
    expected_activity_params.is_main_frame = true;
    expected_activity_params.type = "form_changed";

    EXPECT_EQ(params, expected_activity_params);
  }

  base::HistogramTester histogram_tester_;
  std::unique_ptr<autofill::TestFormActivityObserver> observer_;
};

// Tests that observer is called on form submission using submit control.
TEST_F(FormActivityTabHelperTest, TestObserverDocumentSubmitted) {
  LoadHtml(@"<form name='form-name'>"
            "<input type='submit' id='submit'/>"
            "</form>");

  WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ASSERT_FALSE(observer_->submit_document_info());
  const std::string kTestFormName("form-name");

  std::string mainFrameID = main_frame->GetFrameId();
  const std::string kTestFormData =
      std::string("[{\"name\":\"form-name\",\"origin\":\"https://chromium.test/"
                  "\",\"action\":\"https://chromium.test/\","
                  "\"name_attribute\":\"form-name\",\"id_attribute\":\"\","
                  "\"renderer_id\":\"1\",\"frame_id\":\"") +
      mainFrameID + std::string("\"}]");

  ExecuteJavaScript(@"document.getElementById('submit').click();");
  ASSERT_TRUE(observer_->submit_document_info());
  EXPECT_EQ(web_state(), observer_->submit_document_info()->web_state);
  EXPECT_EQ(main_frame, observer_->submit_document_info()->sender_frame);
  EXPECT_EQ(kTestFormName, observer_->submit_document_info()->form_name);
  EXPECT_EQ(kTestFormData, observer_->submit_document_info()->form_data);

  EXPECT_FALSE(observer_->submit_document_info()->has_user_gesture);

  // Verify that there isn't any form activity metric recorded, even if
  // batching is allowed, as the form submit signals aren't covered.
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount", 0);
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount", 0);
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio", 0);
}

// Tests that observer is called on form submission using submit() method.
TEST_F(FormActivityTabHelperTest, TestFormSubmittedHook) {
  LoadHtml(@"<form name='form-name' id='form'>"
            "<input type='submit'/>"
            "</form>");

  WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ASSERT_FALSE(observer_->submit_document_info());
  const std::string kTestFormName("form-name");

  std::string mainFrameID = main_frame->GetFrameId();
  const std::string kTestFormData =
      std::string("[{\"name\":\"form-name\",\"origin\":\"https://chromium.test/"
                  "\",\"action\":\"https://chromium.test/\","
                  "\"name_attribute\":\"form-name\",\"id_attribute\":\"form\","
                  "\"renderer_id\":\"1\",\"frame_id\":\"") +
      mainFrameID + std::string("\"}]");

  ExecuteJavaScript(@"document.getElementById('form').submit();");
  ASSERT_TRUE(observer_->submit_document_info());
  EXPECT_EQ(web_state(), observer_->submit_document_info()->web_state);
  EXPECT_EQ(main_frame, observer_->submit_document_info()->sender_frame);
  EXPECT_EQ(kTestFormName, observer_->submit_document_info()->form_name);
  EXPECT_EQ(kTestFormData, observer_->submit_document_info()->form_data);
  EXPECT_FALSE(observer_->submit_document_info()->has_user_gesture);

  // Verify that there isn't any form activity metric recorded, even if
  // batching is allowed, as the form submit signals aren't covered.
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount", 0);
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount", 0);
  histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio", 0);
}

// Tests that submit event from same-origin iframe correctly delivered to
// WebStateObserver.
TEST_F(FormActivityTabHelperTest, FormSubmittedFromSameOriginIFrame) {
  LoadHtml(@"<iframe id='frame1'></iframe>");
  ExecuteJavaScript(
      @"document.getElementById('frame1').contentDocument.body.innerHTML = "
       "'<form id=\"form1\">"
       "<input type=\"password\" name=\"password\" id=\"id2\">"
       "<input type=\"submit\" id=\"submit_input\"/>"
       "</form>'");
  ExecuteJavaScript(
      @"document.getElementById('frame1').contentDocument.getElementById('"
      @"submit_input').click();");
  autofill::TestSubmitDocumentInfo* info = observer_->submit_document_info();
  ASSERT_TRUE(info);
  EXPECT_EQ("form1", info->form_name);
}

// Tests that observer is called on form activity (input event).
// TODO(crbug.com/40902648): Disabled test due to bot failure. Re-enable when
// fixed.
TEST_F(FormActivityTabHelperTest,
       DISABLED_TestObserverFormActivityFrameMessaging) {
  LoadHtml(@"<form name='form-name'>"
            "<input type='input' name='field-name' id='fieldid'/>"
            "</form>");

  WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ASSERT_FALSE(observer_->form_activity_info());
  // First call will set document.activeElement (which is usually set by user
  // action. Second call will trigger the message.
  ExecuteJavaScript(@"document.getElementById('fieldid').focus();");
  ASSERT_FALSE(observer_->form_activity_info());
  ExecuteJavaScript(@"document.getElementById('fieldid').focus();");
  ASSERT_TRUE(base::test::ios::WaitUntilConditionOrTimeout(
      base::test::ios::kWaitForJSCompletionTimeout, ^bool {
        return observer_->form_activity_info() != nullptr;
      }));
  EXPECT_EQ(web_state(), observer_->form_activity_info()->web_state);
  EXPECT_EQ(main_frame, observer_->form_activity_info()->sender_frame);
  EXPECT_EQ("form-name",
            observer_->form_activity_info()->form_activity.form_name);
  EXPECT_EQ("text", observer_->form_activity_info()->form_activity.field_type);
  EXPECT_EQ("focus", observer_->form_activity_info()->form_activity.type);
  EXPECT_EQ("", observer_->form_activity_info()->form_activity.value);
  EXPECT_TRUE(observer_->form_activity_info()->form_activity.is_main_frame);
  EXPECT_TRUE(observer_->form_activity_info()->form_activity.has_user_gesture);
}

// Tests that keyup event is not delivered to WebStateObserver if the element is
// not focused.
TEST_F(FormActivityTabHelperTest, KeyUpEventNotFocused) {
  LoadHtml(@"<input id='test'/>");
  ASSERT_FALSE(observer_->form_activity_info());
  ExecuteJavaScript(@"var e = document.getElementById('test');"
                     "var ev = new KeyboardEvent('keyup', {bubbles:true});"
                     "e.dispatchEvent(ev);");

  // Pump the run loop to get the renderer response.
  WaitForBackgroundTasks();

  autofill::TestFormActivityInfo* info = observer_->form_activity_info();
  ASSERT_FALSE(info);
}

// Tests that focus event correctly delivered to WebStateObserver.
TEST_F(FormActivityTabHelperTest, FocusMainFrame) {
  LoadHtml(@"<form>"
            "<input type='text' name='username' id='id1'>"
            "<input type='password' name='password' id='id2'>"
            "</form>");
  ASSERT_FALSE(observer_->form_activity_info());
  ExecuteJavaScript(@"document.getElementById('id1').focus();");
  autofill::TestFormActivityObserver* block_observer = observer_.get();
  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^{
    return block_observer->form_activity_info() != nullptr;
  }));
  autofill::TestFormActivityInfo* info = observer_->form_activity_info();
  ASSERT_TRUE(info);
  EXPECT_EQ("focus", info->form_activity.type);
  EXPECT_FALSE(info->form_activity.input_missing);
}

// Tests that focus event from same-origin iframe correctly delivered to
// WebStateObserver.
TEST_F(FormActivityTabHelperTest, FocusSameOriginIFrame) {
  LoadHtml(@"<iframe id='frame1'></iframe>");
  ExecuteJavaScript(
      @"document.getElementById('frame1').contentDocument.body.innerHTML = "
       "'<form>"
       "<input type=\"text\" name=\"username\" id=\"id1\">"
       "<input type=\"password\" name=\"password\" id=\"id2\">"
       "</form>'");

  ExecuteJavaScript(
      @"document.getElementById('frame1').contentDocument.getElementById('id1')"
      @".focus()");
  autofill::TestFormActivityObserver* block_observer = observer_.get();
  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^{
    return block_observer->form_activity_info() != nullptr;
  }));
  autofill::TestFormActivityInfo* info = observer_->form_activity_info();
  ASSERT_TRUE(info);
  EXPECT_EQ("focus", info->form_activity.type);
  EXPECT_FALSE(info->form_activity.input_missing);
}

// Tests that a new element that contains 'form' in the tag name does not
// trigger a form_changed event.
TEST_F(FormActivityTabHelperTest, AddCustomElement) {
  LoadHtml(@"<body></body>");
  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);
  TrackFormMutations(main_frame);

  ExecuteJavaScript(@"var form = document.createElement('my-form');"
                    @"document.body.appendChild(form);");

  // Check that no activity is observed upon JS completion.
  autofill::TestFormActivityObserver* block_observer = observer_.get();
  __block autofill::TestFormActivityInfo* info = nil;
  EXPECT_FALSE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^{
    info = block_observer->form_activity_info();
    return info != nil;
  }));
}

// Test fixture verifying the behavior of FormActivityTabHelper when handling
// form mutation events.
class FormMutationTest
    : public FormActivityTabHelperTest,
      public testing::WithParamInterface<std::tuple<bool, bool>> {
 public:
  void SetUp() override { FormActivityTabHelperTest::SetUp(); }

 protected:
  // Loads the specified HTML content, prepares for form mutation tracking, and
  // optionally enables XHR submission detection.
  void LoadHtmlForMutationTest(NSString* html) {
    LoadHtml(html);
    web::WebFrame* main_frame = WaitForMainFrame();
    ASSERT_TRUE(main_frame);
    TrackFormMutations(main_frame, IsBatchingAllowed());

    autofill::FormUtilJavaScriptFeature::GetInstance()
        ->SetAutofillXHRSubmissionDetection(main_frame,
                                            IsXHRSubmissionDetectionEnabled());
  }

  /**
   * Removes the specified HTML element from the DOM and returns the
   * corresponding form removal parameters.
   *  - `element_id`  The ID of the HTML element to remove.
   * Retruns an `std::optional` containing the `FormRemovalParams` if the
   * removal was successful and the event was received within the timeout;
   * otherwise, an empty `std::optional`.
   */
  std::optional<autofill::FormRemovalParams> RemoveElement(
      NSString* element_id) {
    ExecuteJavaScript(
        [NSString stringWithFormat:@"document.getElementById('%@').remove();",
                                   element_id]);

    autofill::TestFormActivityObserver* block_observer = observer_.get();
    __block autofill::TestFormRemovalInfo* info = nil;

    // Wait for form removal message delivery.
    bool form_removal_info_received = WaitUntilConditionOrTimeout(
        base::Milliseconds(kTrackFormMutationsDelayInMs * 2), ^{
          info = block_observer->form_removal_info();
          return info != nil;
        });

    if (!form_removal_info_received) {
      return std::nullopt;
    }

    web::WebFrame* main_frame = WaitForMainFrame();
    CHECK(main_frame);

    EXPECT_EQ(web_state(), info->web_state);
    EXPECT_EQ(main_frame, info->sender_frame);
    EXPECT_THAT(info->form_removal_params.frame_id,
                StrEq(main_frame->GetFrameId()));

    return info->form_removal_params;
  }

  // Sets a unique ID for the specified web element if it doesn't already have
  // one.
  void SetElementUniqueID(NSString* element_id) {
    ExecuteJavaScript([NSString
        stringWithFormat:@"var element = document.getElementById('%@');"
                         @"__gCrWeb.fill.setUniqueIDIfNeeded(element);",
                         element_id]);
  }

  // Helper functions to access parameters:
  bool IsBatchingAllowed() const { return std::get<0>(GetParam()); }

  bool IsXHRSubmissionDetectionEnabled() const {
    return std::get<1>(GetParam());
  }
};

// Tests that observer is called on form removal.
TEST_P(FormMutationTest, PasswordFormRemovalRegistered) {
  LoadHtmlForMutationTest(
      @"<form name=\"form1\" id=\"form1\">"
       "<input type=\"text\" name=\"username\" id=\"id1\">"
       "<input type=\"password\" name=\"password\" id=\"id2\">"
       "<input type=\"submit\" id=\"submit_input\"/>"
       "</form>");

  ASSERT_FALSE(observer_->form_removal_info());

  SetElementUniqueID(@"form1");
  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"form1");
  ASSERT_TRUE(form_removal_params);

  EXPECT_THAT(form_removal_params.value().removed_forms,
              ElementsAre(FormRendererId(1)));
  EXPECT_THAT(form_removal_params.value().removed_unowned_fields, IsEmpty());

  if (IsBatchingAllowed()) {
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.DropCount",
                                         /*sample=*/0,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendCount",
                                         /*sample=*/1,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendRatio",
                                         /*sample=*/100,
                                         /*expected_bucket_count=*/1);
  } else {
    // Verify that there isn't any metric recorded as the batching feature is
    // disabled.
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio",
                                       0);
  }

  // Validate that only one removal event is received.
  ASSERT_FALSE(WaitUntilConditionOrTimeout(
      base::Milliseconds(kTrackFormMutationsDelayInMs * 2), ^bool {
        return observer_->number_of_events_received() > 1;
      }));
}

// Tests that removing non-password form triggers
// 'form_removed" event.
TEST_P(FormMutationTest, RemoveNonPasswordForm) {
  // Load html with one form.
  LoadHtmlForMutationTest(@"<form id='form1'>"
                           "<input type='text'>"
                           "</form>");

  // Set form unique ID before removal so the ID is reported in the form removal
  // message sent to the browser.
  SetElementUniqueID(/*element_id=*/@"form1");

  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"form1");

  if (IsXHRSubmissionDetectionEnabled()) {
    ASSERT_TRUE(form_removal_params);
    EXPECT_THAT(form_removal_params.value().removed_forms,
                ElementsAre(FormRendererId(1)));
    EXPECT_THAT(form_removal_params.value().removed_unowned_fields, IsEmpty());
  } else {
    ASSERT_FALSE(form_removal_params);
  }
}

// Tests that removing multiple forms triggers
// 'form_removed" event.
TEST_P(FormMutationTest, RemoveMultipleForms) {
  // Load html with multiple forms.
  LoadHtmlForMutationTest(@"<div id='div'>"
                           "<form id='form1'>"
                           "<input type='password'>"
                           "</form>"
                           "<form id='form2'>"
                           "<input type='text'>"
                           "</form>"
                           "<form id='form3'>"
                           "<input type='email'>"
                           "</form>"
                           "</div>");

  SetElementUniqueID(/*element_id=*/@"form1");
  SetElementUniqueID(/*element_id=*/@"form2");
  SetElementUniqueID(/*element_id=*/@"form3");

  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"div");

  ASSERT_TRUE(form_removal_params);

  const FormRendererId form1_id = FormRendererId(1);
  const FormRendererId form2_id = FormRendererId(2);
  const FormRendererId form3_id = FormRendererId(3);

  if (IsXHRSubmissionDetectionEnabled()) {
    EXPECT_THAT(form_removal_params.value().removed_forms,
                UnorderedElementsAre(form1_id, form2_id, form3_id));

  } else {
    EXPECT_THAT(form_removal_params.value().removed_forms,
                ElementsAre(form1_id));
  }
  EXPECT_THAT(form_removal_params.value().removed_unowned_fields, IsEmpty());
}

// Tests that removing unowned password fields triggers 'password_form_removed"
// event.
TEST_P(FormMutationTest, RemoveFormlessPasswordFields) {
  LoadHtmlForMutationTest(
      @"<body><div>"
       "<input type=\"password\" name=\"password\" id=\"pw\">"
       "<input type=\"submit\" id=\"submit_input\"/>"
       "</div></body>");

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  SetElementUniqueID(@"pw");
  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"pw");

  ASSERT_TRUE(form_removal_params);
  EXPECT_THAT(form_removal_params.value().removed_forms, IsEmpty());
  EXPECT_THAT(form_removal_params.value().removed_unowned_fields,
              ElementsAre(FieldRendererId(1)));
  EXPECT_THAT(form_removal_params.value().frame_id, Not(IsEmpty()));

  if (IsBatchingAllowed()) {
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.DropCount",
                                         /*sample=*/0,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendCount",
                                         /*sample=*/1,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendRatio",
                                         /*sample=*/100,
                                         /*expected_bucket_count=*/1);
  } else {
    // Verify that there isn't any metric recorded as the batching feature is
    // disabled.
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio",
                                       0);
  }

  // Validate that only one removal event is received.
  ASSERT_FALSE(WaitUntilConditionOrTimeout(
      base::Milliseconds(kTrackFormMutationsDelayInMs * 2), ^bool {
        return observer_->number_of_events_received() > 1;
      }));
}

// Tests that removing multiple forms and formless fields triggers
// 'form_removed" event.
TEST_P(FormMutationTest, RemoveMultipleFormsAndFormlessFields) {
  // Load html with multiple forms and formless fields.
  LoadHtmlForMutationTest(@"<div id='div'>"
                           "<form id='form1'>"
                           "<input type='password'/>"
                           "</form>"
                           "<form id='form2'>"
                           "<input type='text'/>"
                           "</form>"
                           "<form id='form3'>"
                           "<input type='email'/>"
                           "</form>"
                           "<input id='password' type='password'/>"
                           "<input id='text' type='text'/>"
                           "</div>");

  SetElementUniqueID(/*element_id=*/@"form1");
  SetElementUniqueID(/*element_id=*/@"form2");
  SetElementUniqueID(/*element_id=*/@"form3");
  SetElementUniqueID(/*element_id=*/@"password");
  SetElementUniqueID(/*element_id=*/@"text");

  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"div");

  ASSERT_TRUE(form_removal_params);

  const FormRendererId form1_id = FormRendererId(1);
  const FormRendererId form2_id = FormRendererId(2);
  const FormRendererId form3_id = FormRendererId(3);
  const FieldRendererId password_id = FieldRendererId(4);
  const FieldRendererId text_id = FieldRendererId(5);

  if (IsXHRSubmissionDetectionEnabled()) {
    EXPECT_THAT(form_removal_params.value().removed_forms,
                UnorderedElementsAre(form1_id, form2_id, form3_id));
    EXPECT_THAT(form_removal_params.value().removed_unowned_fields,
                UnorderedElementsAre(password_id, text_id));

  } else {
    EXPECT_THAT(form_removal_params.value().removed_forms,
                ElementsAre(form1_id));
    EXPECT_THAT(form_removal_params.value().removed_unowned_fields, IsEmpty());
  }
}
// Tests that removing a form control element and adding a new one in the same
// mutations batch is notified with a message for each mutation, sent
// back-to-back, when batching is enabled.
TEST_P(FormMutationTest, RemovedAndAddedFormsRegistered) {
  // Basic HTML page in which we add a HTML form.
  NSString* const html = @"<html><body><form id=\"form1\">"
                          "<input type=\"password\"></form></body></html>";
  LoadHtmlForMutationTest(html);

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ASSERT_FALSE(observer_->form_removal_info());
  ASSERT_FALSE(observer_->form_activity_info());

  // Make a script to create a new form and replace the old form with it.
  NSString* const replace_form_JS =
      @"const newForm = document.createElement('form'); "
       "newForm.id = 'form2'; "
       "const oldForm = document.forms[0]; "
       "__gCrWeb.fill.setUniqueIDIfNeeded(oldForm);"
       "oldForm.parentNode.replaceChild(newForm, oldForm);";

  // Replace the form to trigger an added and a removed form mutation event
  // batched together.
  ExecuteJavaScript(replace_form_JS);

  // Wait until the first message is received.
  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool() {
    return observer_->number_of_events_received() == 1;
  }));

  if (IsBatchingAllowed()) {
    // The removed form message is always the first posted. Skip this when
    // messages batching isn't enabled because the added form comes first in
    // that case.
    ASSERT_TRUE(observer_->form_removal_info());
    FormRemovalParams form_removal_params =
        observer_->form_removal_info()->form_removal_params;
    EXPECT_THAT(form_removal_params.frame_id, Not(IsEmpty()));
    EXPECT_THAT(form_removal_params.removed_unowned_fields, IsEmpty());
    EXPECT_THAT(form_removal_params.removed_forms,
                ElementsAre(FormRendererId(1)));

    // Wait until the next message is received.
    EXPECT_TRUE(
        WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool() {
          return observer_->number_of_events_received() == 2;
        }));
  }

  ASSERT_TRUE(observer_->form_activity_info());
  ValidateParamsAfterFormChangedEvent(
      observer_->form_activity_info()->form_activity);

  if (IsBatchingAllowed()) {
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.DropCount",
                                         /*sample=*/0,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendCount",
                                         /*sample=*/2,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendRatio",
                                         /*sample=*/100,
                                         /*expected_bucket_count=*/1);
  } else {
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio",
                                       0);
  }
}

// Tests that messages that were batched and dropped are correctly recorded as
// such.
TEST_P(FormMutationTest, RemovedAndAddedFormsRegistered_WithDroppedMessages) {
  // Basic HTML page with 2 password forms and one formless password form.
  NSString* const html = @"<html><body><form id=\"form1\">"
                          "<input type=\"password\"></form>"
                          "<form id=\"form2\"><input type=\"password\"></form>"
                          "<input id=\"input1\" type=\"password\">"
                          "</body></html>";
  LoadHtmlForMutationTest(html);

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ASSERT_FALSE(observer_->form_removal_info());
  ASSERT_FALSE(observer_->form_activity_info());

  // Make a script that batches 2 messages and ignore all other cases once full.
  NSString* const add_and_remove_form_JS =
      @"const parentNode = document.forms[0].parentNode; "
       // Add a generic form and remove a password form, both of which will be
       // notified in the same batch.
       "parentNode.appendChild(document.createElement('form')); "
       "const form1 = document.getElementById('form1'); "
       "__gCrWeb.fill.setUniqueIDIfNeeded(form1); "
       "form1.remove(); "
       // Form transformations from here should be ignored.
       // Add non-password form and remove it, 2 notifications dropped.
       "parentNode.appendChild(document.createElement('form')).remove(); "
       // Remove formless password input, 1 notification dropped.
       "document.getElementById('input1').remove();"
       // Remove password form, 1 notification dropped.
       "document.getElementById('form2').remove();";

  ExecuteJavaScript(add_and_remove_form_JS);

  if (IsBatchingAllowed()) {
    // Wait on all the messages in the batch.
    ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool {
      return observer_->form_removal_info() != nullptr &&
             observer_->form_activity_info() != nullptr;
    }));

    EXPECT_THAT(
        observer_->form_removal_info()->form_removal_params.removed_forms,
        ElementsAre(FormRendererId(1)));
    EXPECT_THAT(observer_->form_removal_info()
                    ->form_removal_params.removed_unowned_fields,
                IsEmpty());
    ValidateParamsAfterFormChangedEvent(
        observer_->form_activity_info()->form_activity);

    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.DropCount",
                                         /*sample=*/4,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendCount",
                                         /*sample=*/2,
                                         /*expected_bucket_count=*/1);
    histogram_tester_.ExpectUniqueSample("Autofill.iOS.FormActivity.SendRatio",
                                         /*sample=*/33,
                                         /*expected_bucket_count=*/1);
  } else {
    // Wait on all the messages in the batch.
    ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool {
      return observer_->form_activity_info() != nullptr;
    }));

    EXPECT_THAT(observer_->form_activity_info()->form_activity.frame_id,
                Not(IsEmpty()));
    EXPECT_THAT(observer_->form_activity_info()->form_activity.type,
                StrEq("form_changed"));

    // Verify that there isn't any metric recorded as the batch feature is
    // disabled.
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.DropCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendCount",
                                       0);
    histogram_tester_.ExpectTotalCount("Autofill.iOS.FormActivity.SendRatio",
                                       0);

    // Validate only the form activity message is received when batching is not
    // allowed.
    ASSERT_FALSE(WaitUntilConditionOrTimeout(
        base::Milliseconds(kTrackFormMutationsDelayInMs * 2), ^bool {
          return observer_->number_of_events_received() > 1;
        }));
  }
}

// Tests that removing input fields triggers the right events.
TEST_P(FormMutationTest, RemoveFormlessFields) {
  LoadHtmlForMutationTest(@"<body><div id='div'>"
                           "<input type='password' id='password'/>"
                           "<input type='text' id='text'/>"
                           "<input type='submit' id='submit_input'/>"
                           "<input type='email' id='email'/>"
                           "<input type='tel' id='phone'/>"
                           "<input type='url' id='url'/>"
                           "<input type='number' id='number'/>"
                           "<input type='checkbox' id='checkbox' />"
                           "<input type='radio' id='radio'/>"
                           "<select id='select'>"
                           "  <option value='v1'>v1</option>"
                           "  <option value='v2'>v2</option>"
                           "</select>"
                           "<textarea id='textarea'/>"
                           "</div></body>");

  SetElementUniqueID(/*element_id=*/@"password");
  SetElementUniqueID(/*element_id=*/@"text");
  SetElementUniqueID(/*element_id=*/@"email");
  SetElementUniqueID(/*element_id=*/@"phone");
  SetElementUniqueID(/*element_id=*/@"url");
  SetElementUniqueID(/*element_id=*/@"number");
  SetElementUniqueID(/*element_id=*/@"checkbox");
  SetElementUniqueID(/*element_id=*/@"radio");
  SetElementUniqueID(/*element_id=*/@"select");
  SetElementUniqueID(/*element_id=*/@"textarea");

  std::optional<autofill::FormRemovalParams> form_removal_params =
      RemoveElement(/*element_id=*/@"div");

  ASSERT_TRUE(form_removal_params);
  EXPECT_TRUE(form_removal_params.value().removed_forms.empty());

  const FieldRendererId password_id = FieldRendererId(1);
  const FieldRendererId text_id = FieldRendererId(2);
  const FieldRendererId email_id = FieldRendererId(3);
  const FieldRendererId phone_id = FieldRendererId(4);
  const FieldRendererId url_id = FieldRendererId(5);
  const FieldRendererId number_id = FieldRendererId(6);
  const FieldRendererId checkbox_id = FieldRendererId(7);
  const FieldRendererId radio_id = FieldRendererId(8);
  const FieldRendererId select_id = FieldRendererId(9);
  const FieldRendererId textarea_id = FieldRendererId(10);

  EXPECT_THAT(form_removal_params.value().removed_forms, IsEmpty());

  if (IsXHRSubmissionDetectionEnabled()) {
    EXPECT_THAT(form_removal_params.value().removed_unowned_fields,
                UnorderedElementsAre(password_id, text_id, email_id, phone_id,
                                     url_id, number_id, checkbox_id, radio_id,
                                     select_id, textarea_id));
  } else {
    EXPECT_THAT(form_removal_params.value().removed_unowned_fields,
                ElementsAre(password_id));
    EXPECT_FALSE(observer_->form_activity_info());
  }
}

// Tests that a new form triggers form_changed event.
TEST_P(FormMutationTest, AddForm) {
  LoadHtmlForMutationTest(@"<body></body>");

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  ExecuteJavaScript(@"var form = document.createElement('form');"
                    @"document.body.appendChild(form);");
  autofill::TestFormActivityObserver* block_observer = observer_.get();
  __block autofill::TestFormActivityInfo* info = nil;
  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^{
    info = block_observer->form_activity_info();
    return info != nil;
  }));

  ValidateParamsAfterFormChangedEvent(info->form_activity);
}

INSTANTIATE_TEST_SUITE_P(
    /* No InstantiationName */,
    FormMutationTest,
    ::testing::Combine(::testing::Bool(),  // Batching allowed
                       ::testing::Bool()   // XHR submission detection enabled
                       ));

// Test fixture verifying the behavior of FormActivityTabHelper when handling
// mutations involving form control elements.
class FormMutationFormControlElements
    : public FormActivityTabHelperTest,
      public testing::WithParamInterface<std::tuple<std::string, bool>> {};

// Tests that adding a formless control element is notified as a form changed
// mutation.
TEST_P(FormMutationFormControlElements, AddedFormlessControlElement) {
  // Basic HTML page in which we add HTML form control elements.
  NSString* const html = @"<html><body></body></html>";
  LoadHtml(html);

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  auto [element_tag, allow_batching] = GetParam();
  TrackFormMutations(main_frame, allow_batching);

  // Add the element to the page.
  NSString* const insert_element_JS = [NSString
      stringWithFormat:@"const element = document.createElement('%@'); "
                        "document.body.append(element); ",
                       base::SysUTF8ToNSString(element_tag)];

  ExecuteJavaScript(insert_element_JS);

  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool() {
    return observer_->form_activity_info() != nullptr;
  }));

  ValidateParamsAfterFormChangedEvent(
      observer_->form_activity_info()->form_activity);
}

// Tests that adding a form control element is notified as a form changed
// mutation.
TEST_P(FormMutationFormControlElements, AddedFormControlElement) {
  // Basic HTML page in which we add HTML form control elements.
  NSString* const html = @"<html><body><form id='form'></form></body></html>";
  LoadHtml(html);

  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  auto [element_tag, allow_batching] = GetParam();
  TrackFormMutations(main_frame, allow_batching);

  // Add the element to the page.
  NSString* const insert_element_JS = [NSString
      stringWithFormat:@"const element = document.createElement('%@'); "
                        "document.getElementById('form').append(element); ",
                       base::SysUTF8ToNSString(element_tag)];

  ExecuteJavaScript(insert_element_JS);

  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool() {
    return observer_->form_activity_info() != nullptr;
  }));

  ValidateParamsAfterFormChangedEvent(
      observer_->form_activity_info()->form_activity);
}

TEST_P(FormMutationFormControlElements, RemovedFormControlElement) {
  auto [element_tag, allow_batching] = GetParam();
  // Html with the element to be removed.
  NSString* const html = [NSString
      stringWithFormat:@"<html><body><%@/ id='element-id'></body></html>",
                       base::SysUTF8ToNSString(element_tag)];
  LoadHtml(html);
  web::WebFrame* main_frame = WaitForMainFrame();
  ASSERT_TRUE(main_frame);

  TrackFormMutations(main_frame, allow_batching);

  NSString* const remove_element_JS =
      @"document.getElementById('element-id').remove()";
  ExecuteJavaScript(remove_element_JS);

  ASSERT_TRUE(WaitUntilConditionOrTimeout(kWaitForJSCompletionTimeout, ^bool() {
    return observer_->form_activity_info() != nullptr;
  }));

  ValidateParamsAfterFormChangedEvent(
      observer_->form_activity_info()->form_activity);
}

INSTANTIATE_TEST_SUITE_P(
    /* No InstantiationName */,
    FormMutationFormControlElements,
    ::testing::Combine(
        ::testing::Values("form", "input", "select", "option", "textarea"),
        ::testing::Bool()));
