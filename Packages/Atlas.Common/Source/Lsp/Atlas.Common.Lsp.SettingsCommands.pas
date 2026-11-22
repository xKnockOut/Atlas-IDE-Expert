unit Atlas.Common.Lsp.SettingsCommands;

// Befehle für den Einstellungsdialog des IDE-Plugins (#227). Das Plugin bindet
// Atlas.Common nicht ein; damit es dieselbe Prüfung wie der Server nutzt,
// fragt es ihn:
//   atlas.server.checkSettings [Text, Ort] Meldungen des Parsers zu einem
//                                           Text im Format von atlas.json;
//                                           Ort "global" (settings.json)
//                                           oder "project" (Vorgabe) meldet
//                                           Schlüssel am falschen Ort
//   atlas.server.settingsCatalog [Sprache] die Regeln baut die Komposition
//                                           (TRuleSettingsCatalog), hier kommen
//                                           die Erklärungen der Compilermeldungen
//                                           dazu (AddMessages)

interface

uses
  System.SysUtils,
  System.JSON;

type
  TLspSettingsCommands = class
  public const
    cCheckCommand = 'atlas.server.checkSettings';
    cCatalogCommand = 'atlas.server.settingsCatalog';
  public
    /// <summary>{"valid": Boolean, "issues": [{"line", "character", "message", "error"}]}; Zeilen ab 0. AArguments[1]
    /// = "global" prüft den Text als globale Datei, sonst als atlas.json.</summary>
    class function Check(const AArguments: TJSONArray): TJSONObject; static;
    /// <summary>Erklärungen der Compilermeldungen (#54) als "messages": [{"code", "name", "description", "cause",
    /// "bad", "good", "docWiki"}] in ACatalog; Sprache aus AArguments[0], Delphi-Version (BDS-Nummer wie "37.0")
    /// für den DocWiki-Link aus AArguments[1], ohne Angabe das neueste Release.</summary>
    class procedure AddMessages(ACatalog: TJSONObject; const AArguments: TJSONArray); static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Rules.MessageCatalog,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{ TLspSettingsCommands }

class function TLspSettingsCommands.Check(const AArguments: TJSONArray): TJSONObject;
var
  mIssues, mMisplaced: TArray<TConfigurationIssue>;
  mScope: TConfigurationScope;
  mIssue: TConfigurationIssue;
  mItems: TJSONArray;
  mItem: TJSONObject;
  mValid: Boolean;
begin
  TConfigurationParser.Parse(TJsonRead.FirstText(AArguments), mIssues);
  mScope := TConfigurationScope.Project;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) and
    SameText(AArguments.Items[1].Value, 'global') then
  begin
    mScope := TConfigurationScope.Global;
  end;
  TConfigurationScopes.Filter(TJsonRead.FirstText(AArguments), mScope, mMisplaced);
  mIssues := mIssues + mMisplaced;
  mItems := TJSONArray.Create;
  mValid := True;
  for mIssue in mIssues do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('line', TJSONNumber.Create(mIssue.Range.StartPos.Line));
    mItem.AddPair('character', TJSONNumber.Create(mIssue.Range.StartPos.Character));
    mItem.AddPair('message', mIssue.Message);
    mItem.AddPair('error', TJSONBool.Create(mIssue.IsError));
    mItems.AddElement(mItem);
    if mIssue.IsError then
    begin
      mValid := False;
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('valid', TJSONBool.Create(mValid));
  Result.AddPair('issues', mItems);
end;


/// <summary>Zweites Argument als Text (Delphi-Version); '' ohne.</summary>
function SecondString(const AArguments: TJSONArray): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
  begin
    Result := AArguments.Items[1].Value;
  end;
end;

function MessageJson(const AEntry: TCompilerMessageEntry; const ADelphiVersion: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('code', AEntry.Code);
  Result.AddPair('name', AEntry.Name);
  Result.AddPair('description', AEntry.Description);
  Result.AddPair('cause', AEntry.Cause);
  Result.AddPair('bad', AEntry.Bad);
  Result.AddPair('good', AEntry.Good);
  Result.AddPair('docWiki', TCompilerMessageCatalog.DocWikiUrl(AEntry.Code, ADelphiVersion));
end;

class procedure TLspSettingsCommands.AddMessages(ACatalog: TJSONObject; const AArguments: TJSONArray);
var
  mLanguage: TTextLanguage;
  mMessages: TJSONArray;
  mEntry: TCompilerMessageEntry;
begin
  if not TAtlasLocale.TryParse(TJsonRead.FirstText(AArguments), mLanguage) then
  begin
    mLanguage := TTextLanguage.English;
  end;
  mMessages := TJSONArray.Create;
  for mEntry in TCompilerMessageCatalog.Entries(mLanguage) do
  begin
    mMessages.AddElement(MessageJson(mEntry, SecondString(AArguments)));
  end;
  ACatalog.AddPair('messages', mMessages);
end;

end.
