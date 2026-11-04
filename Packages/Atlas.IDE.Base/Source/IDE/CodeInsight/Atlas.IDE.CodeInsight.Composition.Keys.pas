unit Atlas.IDE.CodeInsight.Composition.Keys;

// Tasten von Atlas: Tastenkürzel der Editorbefehle (#399), eigene Tasten für Vervollständigung und Parameter-Hint
// (#494), Neubelegung nach den Einstellungen und die Beobachtung neuer Packages (#494, #520, #600).

interface

/// <summary>Alle Tasten von Atlas nach den Einstellungen neu belegen; bei Konflikt nur mit Vorrang (#494).</summary>
procedure RebindKeys;
procedure StartEditorKeys;
procedure StopEditorKeys;
function EditorKeysStarted: Boolean;
procedure StartCompletionKey;
procedure StopCompletionKey;
function CompletionKeyStarted: Boolean;
procedure StartSignatureKey;
procedure StopSignatureKey;
function SignatureKeyStarted: Boolean;
/// <summary>Paketbeobachtung und Meldung fremder Vervollständigung (#494).</summary>
procedure WatchKeys;
procedure UnwatchKeys;
function KeysWatched: Boolean;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.Bindings,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Build,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.Palette;

var
  // Tastenkürzel der Editorbefehle (#399).
  EditorKeys: TAtlasIdeEditorKeys;
  // Eigene Tasten für Vervollständigung und Parameter-Hint (#494); ohne Einstellung keine.
  CompletionKey: TAtlasIdeKeyBinding;
  SignatureKey: TAtlasIdeKeyBinding;
  Watched: Boolean;

/// <summary>Tasten von Palette, Prüfung beim Speichern und Editorbefehlen.</summary>
procedure RebindCommandKeys;
begin
  if Palette <> nil then
  begin
    Palette.Rebind;
  end;
  if CheckOnSave <> nil then
  begin
    CheckOnSave.Rebind;
  end;
  if EditorKeys <> nil then
  begin
    EditorKeys.Rebind;
  end;
end;

/// <summary>Eigene Tasten für Vervollständigung und Parameter-Hint nach den Einstellungen.</summary>
procedure RebindCodeInsightKeys;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  if CompletionKey <> nil then
  begin
    CompletionKey.Rebind(Word(mSettings.CompletionKey), mSettings.CompletionKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsCompletionKey));
  end;
  if SignatureKey <> nil then
  begin
    SignatureKey.Rebind(Word(mSettings.SignatureKey), mSettings.SignatureKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsSignatureKey));
  end;
end;

procedure RebindKeys;
begin
  RebindCommandKeys;
  RebindCodeInsightKeys;
  if QuickToggles <> nil then
  begin
    QuickToggles.Rebind;
  end;
  if DiagnosticMode <> nil then
  begin
    DiagnosticMode.Rebind;
  end;
end;

procedure StartEditorKeys;
begin
  EditorKeys := TAtlasIdeEditorKeys.Create;
end;

procedure StopEditorKeys;
begin
  FreeAndNil(EditorKeys);
end;

function EditorKeysStarted: Boolean;
begin
  Result := EditorKeys <> nil;
end;

procedure OpenCompletion;
begin
  if Manager <> nil then
  begin
    Manager.OpenCompletion;
  end;
end;

procedure OpenSignature;
begin
  if Manager <> nil then
  begin
    Manager.OpenSignature;
  end;
end;

procedure StartCompletionKey;
begin
  CompletionKey := TAtlasIdeKeyBinding.Create('Atlas.Completion', 'Atlas-Vervollständigung',
    TAtlasFeature.Completion, OpenCompletion);
end;

procedure StopCompletionKey;
begin
  FreeAndNil(CompletionKey);
end;

function CompletionKeyStarted: Boolean;
begin
  Result := CompletionKey <> nil;
end;

procedure StartSignatureKey;
begin
  SignatureKey := TAtlasIdeKeyBinding.Create('Atlas.Signature', 'Atlas-Parameter-Hint', TAtlasFeature.Signature,
    OpenSignature);
end;

procedure StopSignatureKey;
begin
  FreeAndNil(SignatureKey);
end;

function SignatureKeyStarted: Boolean;
begin
  Result := SignatureKey <> nil;
end;

procedure ReportForeignCompletion;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasIdeKeys.ReportForeignCompletion;
    end);
end;

/// <summary>Neue Packages können Tasten belegen oder eine eigene Vervollständigung mitbringen (#494): neu belegen,
/// gegen die Atlas-Tasten prüfen (#520) und die Tastenkürzel-Tipps nachführen (#600).</summary>
procedure PackagesChanged;
begin
  RebindKeys;
  TAtlasIdeKeys.ReportForeignCompletion;
  if KeyMap <> nil then
  begin
    KeyMap.CheckNow;
  end;
  if ShortcutTips <> nil then
  begin
    ShortcutTips.KeysChanged;
  end;
end;

procedure WatchKeys;
begin
  Watched := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings, ReportForeignCompletion);
  TAtlasIdeKeys.WatchPackages(PackagesChanged);
end;

procedure UnwatchKeys;
begin
  TAtlasIdeKeys.UnwatchPackages;
  Watched := False;
end;

function KeysWatched: Boolean;
begin
  Result := Watched;
end;

end.
