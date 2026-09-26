#!/usr/bin/env python3
"""Builds the Back Tap shortcut: [Take Screenshot] -> [AI Keyboard: Suhbatni tahlil qil].

Output is unsigned; sign it on a Mac signed into iCloud:
  shortcuts sign --mode anyone --input build/AIKeyboard-unsigned.shortcut --output "App/Resources/AI Keyboard.shortcut"
The imported shortcut is named after the file.
"""
import os
import plistlib
import uuid

BUNDLE_ID = "com.ibrokhim.dmtranslator"
TEAM_ID = "2Y273CFX36"
INTENT = "AnalyzeChatIntent"

screenshot_uuid = str(uuid.uuid4()).upper()

actions = [
    {
        "WFWorkflowActionIdentifier": "is.workflow.actions.takescreenshot",
        "WFWorkflowActionParameters": {"UUID": screenshot_uuid},
    },
    {
        # Same shape Shortcuts writes for third-party App Intents: "<bundle id>.<intent type name>".
        "WFWorkflowActionIdentifier": f"{BUNDLE_ID}.{INTENT}",
        "WFWorkflowActionParameters": {
            "UUID": str(uuid.uuid4()).upper(),
            "AppIntentDescriptor": {
                "AppIntentIdentifier": INTENT,
                "BundleIdentifier": BUNDLE_ID,
                "Name": "AI Keyboard",
                "TeamIdentifier": TEAM_ID,
            },
            # Parameter key = the @Parameter property name in AnalyzeChatIntent.
            "screenshot": {
                "Value": {"OutputName": "Screenshot", "OutputUUID": screenshot_uuid, "Type": "ActionOutput"},
                "WFSerializationType": "WFTextTokenAttachment",
            },
        },
    },
]

shortcut = {
    "WFWorkflowActions": actions,
    "WFWorkflowClientVersion": "4018.0.4",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 59726, "WFWorkflowIconStartColor": 463140863},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFQuickActionSurfaces": [],
}

out = os.path.join(os.path.dirname(__file__), "..", "build", "AIKeyboard-unsigned.shortcut")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "wb") as f:
    plistlib.dump(shortcut, f, fmt=plistlib.FMT_BINARY)
print(os.path.abspath(out))
