unit Atlas.Common.Lsp.CompilerFixes;

// Schnellkorrekturen für Compilermeldungen über das Protokoll (#549): Code-
// Aktionen mit Änderung auf den Zeilen der Auswahl, an denen der letzte
// Compilerlauf (atlas/compilerMessages, #528) eine Meldung mit Korrektur
// hinterlassen hat, nur mit refactoring.compilerFixes. Gibt es dieselbe
// Nummer mehrmals in der Datei, dazu „Alle … in der Datei beheben“ als eine
// Änderung. Die Korrekturen selbst stehen in Atlas.Common.Editing.
// CompilerFixes; das Plugin übernimmt jede Aktion als einen Rückgängig-
// Schritt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CompilerFixes;

type
  /// <summary>Datei und Auswahl, für die Korrekturen gesucht werden.</summary>
  TCompilerFixRequest = record
    Text: string;
    Tree: TSyntaxTree;
    Uri: string;
    Range: TTextRange;
    Context: TCompilerFixContext;
  end;

  TLspCompilerFixes = class
  public
    /// <summary>Meldungen in der Form der Korrekturen.</summary>
    class function FixMessages(const AMessages: TArray<TCompilerMessage>): TArray<TFixMessage>; static;
    /// <summary>Code-Aktionen für die Meldungen AMessages der Datei ARequest.Uri auf den Zeilen von
    /// ARequest.Range.</summary>
    class function Actions(AEnabled: Boolean; const ARequest: TCompilerFixRequest;
      const AMessages: TArray<TCompilerMessage>): TArray<TJSONObject>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.CodeActions;

class function TLspCompilerFixes.FixMessages(const AMessages: TArray<TCompilerMessage>): TArray<TFixMessage>;
var
  Message: TCompilerMessage;
begin
  Result := nil;
  for Message in AMessages do
  begin
    if Message.Line >= 0 then
    begin
      Result := Result + [TFixMessage.Create(Message.Code, Message.Line, Message.Column, Message.Text)];
    end;
  end;
end;

function ToAction(const AUri: string; const AFix: TCompilerFix): TJSONObject;
var
  Action: TCodeAction;
begin
  Action := Default(TCodeAction);
  Action.Title := AFix.Title;
  Action.Kind := QuickFixKind;
  Action.Edits := AFix.Edits;
  Action.IsPreferred := AFix.Preferred;
  Result := TLspCodeActions.ActionToJson(AUri, Action);
end;

/// <summary>Steht APosition auf dem Bezeichner AName? Dann bietet die uses-Aktion (#284) die Units schon an.
/// </summary>
function OnName(ATree: TSyntaxTree; const APosition: TTextPosition; const AName: string): Boolean;
var
  Token: TPascalToken;
begin
  for Token in ATree.Tokens do
  begin
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.StartPos.Line = APosition.Line) and
      (Token.StartPos.Character <= APosition.Character) and (APosition.Character <= Token.EndPos.Character) then
    begin
      Exit(SameText(Token.Text, AName));
    end;
  end;
  Result := False;
end;

/// <summary>Meldung AMessage bekommt Aktionen: auf den Zeilen der Auswahl, noch nicht gesehen und nicht schon
/// von der uses-Aktion abgedeckt. Merkt sie sich in ASeen.</summary>
function Wanted(const ARequest: TCompilerFixRequest; const AMessage: TFixMessage; var ASeen: TArray<string>): Boolean;
var
  mKey: string;
  mNames: TArray<string>;
begin
  if (AMessage.Line < ARequest.Range.StartPos.Line) or (AMessage.Line > ARequest.Range.EndPos.Line) then
  begin
    Exit(False);
  end;
  // Dieselbe Meldung kommt bei mehreren Plattformen doppelt.
  mKey := AMessage.Code + '@' + IntToStr(AMessage.Line) + '@' + AMessage.Text;
  if IndexText(mKey, ASeen) >= 0 then
  begin
    Exit(False);
  end;
  ASeen := ASeen + [mKey];
  if AMessage.Code <> 'E2003' then
  begin
    Exit(True);
  end;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  Result := (Length(mNames) = 0) or not OnName(ARequest.Tree, ARequest.Range.StartPos, mNames[0]);
end;

class function TLspCompilerFixes.Actions(AEnabled: Boolean; const ARequest: TCompilerFixRequest;
  const AMessages: TArray<TCompilerMessage>): TArray<TJSONObject>;
var
  mMessages: TArray<TFixMessage>;
  mMessage: TFixMessage;
  mItem: TCompilerFix;
  mSeen, mCounted: TArray<string>;
begin
  Result := nil;
  if not AEnabled or (ARequest.Tree = nil) then
  begin
    Exit;
  end;
  mMessages := FixMessages(AMessages);
  mSeen := nil;
  mCounted := nil;
  for mMessage in mMessages do
  begin
    if not Wanted(ARequest, mMessage, mSeen) then
    begin
      Continue;
    end;
    for mItem in TCompilerFixes.Fixes(ARequest.Text, ARequest.Tree, mMessage, ARequest.Context) do
    begin
      Result := Result + [ToAction(ARequest.Uri, mItem)];
    end;
    if not TCompilerFixes.CanFixAll(mMessage.Code) or (IndexText(mMessage.Code, mCounted) >= 0) then
    begin
      Continue;
    end;
    mCounted := mCounted + [mMessage.Code];
    if TCompilerFixes.FixAll(ARequest.Text, ARequest.Tree, mMessages, mMessage.Code, ARequest.Context, mItem) then
    begin
      Result := Result + [ToAction(ARequest.Uri, mItem)];
    end;
  end;
end;

end.
