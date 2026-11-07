unit Atlas.Common.Editing.UsesCommand;

// Schnellbefehl /uses (#254), ohne Protokollbezug.
//
// Eine Zeile "/uses System.SysUtils, Vcl.Forms" (Semikolon erlaubt) wird nach
// Enter gelöscht und die Units kommen über TUsesClauses ins uses des
// Abschnitts, in dem die Zeile stand. Schon eingebundene Units entfallen.
// Die Befehlszeile wird vor dem Zerlegen durch Leerzeichen ersetzt, damit ihr
// "uses" nicht als uses-Liste gilt und alle Positionen gleich bleiben.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  TUsesCommand = class
  public
    /// <summary>Unit-Namen aus einer Befehlszeile; False, wenn die Zeile kein /uses ist.</summary>
    class function Parse(const ALine: string; out AUnits: TArray<string>): Boolean; static;
    /// <summary>Edits nach Enter in Zeile APosition.Line: Befehlszeile darüber löschen und
    /// Units eintragen. False, wenn die Zeile darüber kein /uses ist.</summary>
    class function AfterEnter(const AText: string; const APosition: TTextPosition;
      const ANamespaces: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesClause,
  Atlas.Text.Lines;

function IsUnitName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AName <> '';
  for mIndex := 1 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit(False);
    end;
  end;
  Result := Result and not CharInSet(AName[1], ['0'..'9', '.']) and (AName[Length(AName)] <> '.');
end;

class function TUsesCommand.Parse(const ALine: string; out AUnits: TArray<string>): Boolean;
var
  mRest, mName: string;
begin
  AUnits := nil;
  mRest := Trim(ALine);
  if not mRest.StartsWith('/uses ', True) then
  begin
    Exit(False);
  end;
  mRest := Trim(Copy(mRest, 7, MaxInt));
  if mRest.EndsWith(';') then
  begin
    mRest := Trim(Copy(mRest, 1, Length(mRest) - 1));
  end;
  for mName in mRest.Split([',']) do
  begin
    if not IsUnitName(Trim(mName)) then
    begin
      Exit(False);
    end;
    AUnits := AUnits + [Trim(mName)];
  end;
  Result := Length(AUnits) > 0;
end;

class function TUsesCommand.AfterEnter(const AText: string; const APosition: TTextPosition;
  const ANamespaces: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines, mUnits, mUsed, mMissing: TArray<string>;
  mLine, mOffset, mIndex: Integer;
  mLineBreak, mBlanked, mName: string;
  mTokens: TArray<TPascalToken>;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  mLine := APosition.Line - 1;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLines := AText.Split([mLineBreak]);
  if (mLine < 0) or (mLine >= High(mLines) + 1) or not Parse(mLines[mLine], mUnits) then
  begin
    Exit(False);
  end;
  mOffset := 0;
  for mIndex := 0 to mLine - 1 do
  begin
    Inc(mOffset, Length(mLines[mIndex]) + Length(mLineBreak));
  end;
  mBlanked := Copy(AText, 1, mOffset) + StringOfChar(' ', Length(mLines[mLine])) +
    Copy(AText, mOffset + Length(mLines[mLine]) + 1, MaxInt);
  mTokens := TPascalLexer.Tokenize(mBlanked);
  mUsed := TUsesClauses.UsedUnits(mTokens);
  mMissing := nil;
  for mName in mUnits do
  begin
    if not TUsesClauses.IsUsed(mUsed + mMissing, mName, ANamespaces) then
    begin
      mMissing := mMissing + [mName];
    end;
  end;
  // Die Befehlszeile samt Zeilenende verschwindet in jedem Fall.
  AEdits := [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(mLine, 0), TTextPosition.Create(mLine + 1, 0)),
    '')];
  if (Length(mMissing) > 0) and
    TUsesClauses.AddUnit(mTokens, mOffset, string.Join(', ', mMissing), mLineBreak, mEdit) then
  begin
    AEdits := [mEdit] + AEdits;
  end;
  Result := True;
end;

end.
