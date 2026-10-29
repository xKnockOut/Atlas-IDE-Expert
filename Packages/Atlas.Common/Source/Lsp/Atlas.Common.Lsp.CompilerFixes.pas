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
  TLspCompilerFixes = class
  public
    /// <summary>Meldungen in der Form der Korrekturen.</summary>
    class function FixMessages(const AMessages: TArray<TCompilerMessage>): TArray<TFixMessage>; static;
    /// <summary>Code-Aktionen für die Meldungen AMessages der Datei AUri auf den Zeilen von ARange.</summary>
    class function Actions(AEnabled: Boolean; const AText: string; ATree: TSyntaxTree; const AUri: string;
      const ARange: TTextRange; const AMessages: TArray<TCompilerMessage>;
      const AContext: TCompilerFixContext): TArray<TJSONObject>; static;
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
    if Message.Line >= 0 then
      Result := Result + [TFixMessage.Create(Message.Code, Message.Line, Message.Column, Message.Text)];
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
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.StartPos.Line = APosition.Line) and
      (Token.StartPos.Character <= APosition.Character) and (APosition.Character <= Token.EndPos.Character) then
      Exit(SameText(Token.Text, AName));
  Result := False;
end;

class function TLspCompilerFixes.Actions(AEnabled: Boolean; const AText: string; ATree: TSyntaxTree;
  const AUri: string; const ARange: TTextRange; const AMessages: TArray<TCompilerMessage>;
  const AContext: TCompilerFixContext): TArray<TJSONObject>;
var
  Messages: TArray<TFixMessage>;
  Message: TFixMessage;
  Item: TCompilerFix;
  Seen, Counted: TArray<string>;
  Key: string;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) then
    Exit;
  Messages := FixMessages(AMessages);
  Seen := nil;
  Counted := nil;
  for Message in Messages do
  begin
    if (Message.Line < ARange.StartPos.Line) or (Message.Line > ARange.EndPos.Line) then
      Continue;
    // Dieselbe Meldung kommt bei mehreren Plattformen doppelt.
    Key := Message.Code + '@' + IntToStr(Message.Line) + '@' + Message.Text;
    if IndexText(Key, Seen) >= 0 then
      Continue;
    Seen := Seen + [Key];
    if (Message.Code = 'E2003') and (Length(TCompilerFixes.QuotedNames(Message.Text)) > 0) and
      OnName(ATree, ARange.StartPos, TCompilerFixes.QuotedNames(Message.Text)[0]) then
      Continue;
    for Item in TCompilerFixes.Fixes(AText, ATree, Message, AContext) do
      Result := Result + [ToAction(AUri, Item)];
    if TCompilerFixes.CanFixAll(Message.Code) and (IndexText(Message.Code, Counted) < 0) then
    begin
      Counted := Counted + [Message.Code];
      if TCompilerFixes.FixAll(AText, ATree, Messages, Message.Code, AContext, Item) then
        Result := Result + [ToAction(AUri, Item)];
    end;
  end;
end;

end.
