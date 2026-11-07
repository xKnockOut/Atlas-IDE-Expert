unit Atlas.Common.Lsp.ResourceStringCommands;

// Befehl zu „Als resourcestring auslagern“ (#473) für workspace/executeCommand:
//   atlas.server.addResourceString [datei, name, wert]: trägt "name = wert;"
//     in den resourcestring-Abschnitt im interface-Teil der Datei ein (legt ihn
//     vor implementation an, wenn er fehlt). Die Vervollständigung schickt den
//     Befehl, wenn completion.resourceStringUnit eine andere Unit festlegt;
//     Bezeichner und uses-Eintrag setzt sie selbst. Gibt es den Namen dort
//     schon mit demselben Text, ändert sich nichts.
// Geschrieben wird über den Aufrufer (in der IDE über workspace/applyEdit in
// den Puffer, #397).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  TResourceStringRead = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Schreibt AEdit in AFileName; ANewText ist der Text danach (für das Schreiben ohne Editor).</summary>
  TResourceStringWrite = reference to procedure(const AFileName, ANewText: string; const AEdit: TTextEdit);

  TResourceStringCommands = class
  public const
    cAddCommand = 'atlas.server.addResourceString';
  public
    /// <summary>Änderung für "AName = AValue;" im interface-Teil von AText. False ohne Änderung (gleicher Eintrag
    /// schon da); Ausnahme EJsonRpcError, wenn es AName mit anderem Text gibt oder implementation fehlt.</summary>
    class function AddEdit(const AText, AName, AValue: string; out AEdit: TTextEdit): Boolean; static;
    /// <summary>AEdit auf AText angewandt (Zeilen mit #10, #13 bleibt erhalten).</summary>
    class function Applied(const AText: string; const AEdit: TTextEdit): string; static;
    class function ExecuteAdd(const ARead: TResourceStringRead; const AWrite: TResourceStringWrite;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.ResourceStrings,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TResourceStringCommandsText = (AlreadyExistsThereWithA, TheUnitHasNoImplementation, FileNameAndValueExpected,
    InvalidNameOrEmptyValue, FileNotReadable);

const
  cTexts: array[TResourceStringCommandsText] of TAtlasText = (
    (De: '%s gibt es dort schon mit anderem Text'; En: '%s already exists there with a different text'),
    (De: 'Die Unit hat keinen implementation-Teil'; En: 'The unit has no implementation part'),
    (De: 'Erwartet werden Datei, Name und Wert'; En: 'File, name and value expected'),
    (De: 'Ungültiger Name oder leerer Wert'; En: 'Invalid name or empty value'),
    (De: 'Datei nicht lesbar: '; En: 'File not readable: '));

{$SCOPEDENUMS OFF}

class function TResourceStringCommands.AddEdit(const AText, AName, AValue: string; out AEdit: TTextEdit): Boolean;
var
  mEntry: TResourceEntry;
  mLineBreak: string;
  mTokens: TArray<TPascalToken>;
begin
  AEdit := Default(TTextEdit);
  mTokens := TPascalLexer.Tokenize(AText);
  for mEntry in TResourceStrings.Entries(AText, mTokens) do
  begin
    if SameText(mEntry.Name, AName) then
    begin
      if mEntry.Value = AValue then
      begin
        Exit(False);
      end;
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
        cTexts[TResourceStringCommandsText.AlreadyExistsThereWithA].Fmt([AName]));
    end;
  end;
  mLineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  if not TResourceStrings.Insertion(AText, mTokens, TResourcePlace.Create(True, -1), Format('%s = %s;', [AName, AValue]),
    mLineBreak, AEdit) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TResourceStringCommandsText.TheUnitHasNoImplementation].Text);
  end;
  Result := True;
end;

class function TResourceStringCommands.Applied(const AText: string; const AEdit: TTextEdit): string;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    mLine, mIndex: Integer;
  begin
    mLine := 0;
    mIndex := 1;
    while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
    begin
      if AText[mIndex] = #10 then
      begin
        Inc(mLine);
      end;
      Inc(mIndex);
    end;
    Result := mIndex - 1 + APosition.Character;
  end;

var
  mStart, mStop: Integer;
begin
  mStart := OffsetOf(AEdit.Range.StartPos);
  mStop := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart) + AEdit.NewText + Copy(AText, mStop + 1, MaxInt);
end;

class function TResourceStringCommands.ExecuteAdd(const ARead: TResourceStringRead;
  const AWrite: TResourceStringWrite; const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mName, mValue, mText: string;
  mEdit: TTextEdit;
begin
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONString) or not (AArguments.Items[2] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TResourceStringCommandsText.FileNameAndValueExpected].Text);
  end;
  mFileName := AArguments.Items[0].Value;
  mName := AArguments.Items[1].Value;
  mValue := AArguments.Items[2].Value;
  if not IsValidIdent(mName) or (mValue = '') then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TResourceStringCommandsText.InvalidNameOrEmptyValue].Text);
  end;
  if not ARead(mFileName, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TResourceStringCommandsText.FileNotReadable].Text + ExtractFileName(mFileName));
  end;
  if AddEdit(mText, mName, mValue, mEdit) then
  begin
    AWrite(mFileName, Applied(mText, mEdit), mEdit);
    Exit(TJSONBool.Create(True));
  end;
  Result := TJSONBool.Create(False);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ResourceStringCommands', cTexts);

end.
