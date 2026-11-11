unit Atlas.Core.Designer.Usages;

// Verwendungen einer Komponente im Code (#750), ohne IDE:
// - KindAt ordnet einen Fundort der Referenzsuche ein: „schreibt“ bei einer
//   Zuweisung an die Komponente oder eine Eigenschaft, „Ereignis“ bei einer
//   Zuweisung an eine On…-Eigenschaft, „übergibt“, wenn die Komponente selbst
//   ohne Eigenschaft dasteht (Argument, Sender-Vergleich, with, rechte Seite
//   einer Zuweisung), sonst „liest“ (Eigenschaft gelesen, Methode gerufen).
// - FieldLine findet die Felddeklaration in der Formular-Klasse; von dort
//   fragt die IDE die Referenzsuche.
// - HandlerLine findet die Implementierung eines Handlers aus der DFM.
// - InScope filtert nach Suchbereich: Unit des Formulars, Projekt,
//   Projektgruppe.

interface

type
{$SCOPEDENUMS ON}
  TAtlasUsageKind = (Reads, Writes, Passes, Event);
  TAtlasUsageScope = (UnitOnly, Project, ProjectGroup);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Zugriff auf eine Komponente im Code; Line und Character 0-basiert.</summary>
  TAtlasUsage = record
    Component: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    Kind: TAtlasUsageKind;
    /// <summary>Methode, in der die Zeile liegt; '' außerhalb.</summary>
    Method: string;
    Preview: string;
  end;

  TAtlasDesignerUsages = class
  public
    /// <summary>Art des Zugriffs auf den Namen, der in ALine an ACharacter (0-basiert) beginnt.</summary>
    class function KindAt(const ALine: string; ACharacter: Integer): TAtlasUsageKind; static;
    /// <summary>Zeile (0-basiert) der Felddeklaration AName in der Klasse AClassName; -1 ohne. ACharacter: Beginn
    /// des Namens (0-basiert).</summary>
    class function FieldLine(const ALines: TArray<string>; const AClassName, AName: string;
      out ACharacter: Integer): Integer; static;
    /// <summary>Zeile (0-basiert) von „procedure AClassName.AMethod“ im Implementierungsteil; -1 ohne.</summary>
    class function HandlerLine(const ALines: TArray<string>; const AClassName, AMethod: string): Integer; static;
    /// <summary>Gehört AFileName zum Bereich? AProjectFiles: Dateien des aktiven Projekts.</summary>
    class function InScope(AScope: TAtlasUsageScope; const AFileName, AFormUnit: string;
      const AProjectFiles: TArray<string>): Boolean; static;
    /// <summary>Nach Komponente, Datei und Zeile geordnet.</summary>
    class function Sorted(const AUsages: TArray<TAtlasUsage>): TArray<TAtlasUsage>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Text.Chars;

const
  /// <summary>Vorsilbe eines Ereignisnamens.</summary>
  cEventPrefix = 'On';

/// <summary>Leerzeichen ab APos (1-basiert) überspringen.</summary>
function SkipBlanks(const ALine: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result <= Length(ALine)) and ((ALine[Result] = ' ') or (ALine[Result] = #9)) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Hinter einer Klammer ab APos (1-basiert, auf „(“ oder „[“): Position nach der passenden schließenden.
/// </summary>
function SkipBracket(const ALine: string; APos: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := APos;
  while Result <= Length(ALine) do
  begin
    if CharInSet(ALine[Result], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(ALine[Result], [')', ']']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Result + 1);
      end;
    end;
    Inc(Result);
  end;
end;

/// <summary>Ende (1-basiert, hinter dem letzten Zeichen) des Bezeichners ab APos.</summary>
function IdentEnd(const ALine: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result <= Length(ALine)) and TTextChars.IsIdentChar(ALine[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Folgt der Kette „.Eigenschaft“, „[Index]“ und „(Argumente)“ hinter dem Namen. AMembers zählt die
/// Eigenschaften, ALast ist die letzte; Ergebnis: Position dahinter.</summary>
function FollowChain(const ALine: string; APos: Integer; out AMembers: Integer; out ALast: string): Integer;
var
  mNext, mStop: Integer;
begin
  AMembers := 0;
  ALast := '';
  Result := APos;
  while True do
  begin
    mNext := SkipBlanks(ALine, Result);
    if mNext > Length(ALine) then
    begin
      Exit;
    end;
    if CharInSet(ALine[mNext], ['(', '[']) then
    begin
      Result := SkipBracket(ALine, mNext);
      Continue;
    end;
    if ALine[mNext] <> '.' then
    begin
      Exit;
    end;
    mNext := SkipBlanks(ALine, mNext + 1);
    mStop := IdentEnd(ALine, mNext);
    if mStop = mNext then
    begin
      Exit;
    end;
    ALast := Copy(ALine, mNext, mStop - mNext);
    Inc(AMembers);
    Result := mStop;
  end;
end;

/// <summary>„OnClick“, „OnChange“: Name eines Ereignisses.</summary>
function IsEventName(const AName: string): Boolean;
begin
  Result := (Length(AName) > Length(cEventPrefix)) and StartsText(cEventPrefix, AName) and
    CharInSet(AName[Length(cEventPrefix) + 1], ['A'..'Z']);
end;

class function TAtlasDesignerUsages.KindAt(const ALine: string; ACharacter: Integer): TAtlasUsageKind;
var
  mPos, mMembers: Integer;
  mLast: string;
begin
  mPos := FollowChain(ALine, IdentEnd(ALine, ACharacter + 1), mMembers, mLast);
  mPos := SkipBlanks(ALine, mPos);
  if Copy(ALine, mPos, 2) = ':=' then
  begin
    if (mMembers > 0) and IsEventName(mLast) then
    begin
      Exit(TAtlasUsageKind.Event);
    end;
    Exit(TAtlasUsageKind.Writes);
  end;
  if mMembers = 0 then
  begin
    Result := TAtlasUsageKind.Passes;
  end
  else
  begin
    Result := TAtlasUsageKind.Reads;
  end;
end;

/// <summary>Beginnt in ALine die Klasse AClassName („TfrmX = class“)?</summary>
function StartsClass(const ALine, AClassName: string): Boolean;
var
  mText, mRest: string;
begin
  mText := Trim(ALine);
  if not StartsText(AClassName, mText) then
  begin
    Exit(False);
  end;
  mRest := LowerCase(StringReplace(Copy(mText, Length(AClassName) + 1, MaxInt), ' ', '', [rfReplaceAll]));
  // Vorwärtsdeklaration „TfrmX = class;“ hat keinen Rumpf.
  Result := StartsText('=class', mRest) and not StartsText('=class;', mRest) and not StartsText('=classof', mRest);
end;

/// <summary>Beginn (1-basiert) von AName in der Liste vor dem Doppelpunkt („a, b: TEdit“); 0 ohne.</summary>
function NameInFieldList(const ALine, AName: string): Integer;
var
  mColon, mPos, mStop: Integer;
begin
  Result := 0;
  mColon := Pos(':', ALine);
  if (mColon = 0) or (Copy(ALine, mColon, 2) = ':=') then
  begin
    Exit;
  end;
  mPos := SkipBlanks(ALine, 1);
  while mPos < mColon do
  begin
    mStop := IdentEnd(ALine, mPos);
    if mStop = mPos then
    begin
      Exit;
    end;
    if SameText(Copy(ALine, mPos, mStop - mPos), AName) then
    begin
      Exit(mPos);
    end;
    mPos := SkipBlanks(ALine, mStop);
    if (mPos < mColon) and (ALine[mPos] = ',') then
    begin
      mPos := SkipBlanks(ALine, mPos + 1);
    end
    else
    begin
      Exit;
    end;
  end;
end;

class function TAtlasDesignerUsages.FieldLine(const ALines: TArray<string>; const AClassName, AName: string;
  out ACharacter: Integer): Integer;
var
  mLine, mPos: Integer;
  mInClass: Boolean;
begin
  ACharacter := -1;
  mInClass := False;
  for mLine := 0 to High(ALines) do
  begin
    if not mInClass then
    begin
      mInClass := StartsClass(ALines[mLine], AClassName);
      Continue;
    end;
    if SameText(Trim(ALines[mLine]), 'end;') then
    begin
      Break;
    end;
    mPos := NameInFieldList(ALines[mLine], AName);
    if mPos > 0 then
    begin
      ACharacter := mPos - 1;
      Exit(mLine);
    end;
  end;
  Result := -1;
end;

class function TAtlasDesignerUsages.HandlerLine(const ALines: TArray<string>; const AClassName,
  AMethod: string): Integer;
var
  mLine: Integer;
  mText, mHead: string;
begin
  mHead := LowerCase(AClassName + '.' + AMethod);
  for mLine := 0 to High(ALines) do
  begin
    mText := LowerCase(Trim(ALines[mLine]));
    if StartsText('procedure ', mText) or StartsText('function ', mText) then
    begin
      mText := Trim(Copy(mText, Pos(' ', mText) + 1, MaxInt));
      if StartsText(mHead, mText) and ((Length(mText) = Length(mHead)) or
        not TTextChars.IsIdentChar(mText[Length(mHead) + 1])) then
      begin
        Exit(mLine);
      end;
    end;
  end;
  Result := -1;
end;

class function TAtlasDesignerUsages.InScope(AScope: TAtlasUsageScope; const AFileName, AFormUnit: string;
  const AProjectFiles: TArray<string>): Boolean;
var
  mFile: string;
begin
  if SameText(AFileName, AFormUnit) or (AScope = TAtlasUsageScope.ProjectGroup) then
  begin
    Exit(True);
  end;
  if AScope = TAtlasUsageScope.UnitOnly then
  begin
    Exit(False);
  end;
  for mFile in AProjectFiles do
  begin
    if SameText(mFile, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDesignerUsages.Sorted(const AUsages: TArray<TAtlasUsage>): TArray<TAtlasUsage>;
begin
  Result := Copy(AUsages);
  TArray.Sort<TAtlasUsage>(Result, TComparer<TAtlasUsage>.Construct(
    function(const ALeft, ARight: TAtlasUsage): Integer
    begin
      Result := CompareText(ALeft.Component, ARight.Component);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.FileName, ARight.FileName);
      end;
      if Result = 0 then
      begin
        Result := ALeft.Line - ARight.Line;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Character - ARight.Character;
      end;
    end));
end;

end.
