unit Atlas.Common.Rules.Builtin.Declarations.Shared;

// Gemeinsame Hilfen der Deklarationsregeln (Atlas.Common.Rules.Builtin.Declarations und ihre Teilunits):
// Token zu einem Offset, Leerraum vor und hinter einer Stelle, Aufzählung "A, B und C", Name ohne Vorsatz.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
/// <summary>Steht vor APosition in ihrer Zeile nur Leerraum?</summary>
function BlankBefore(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
/// <summary>Steht hinter APosition in ihrer Zeile nur Leerraum oder ein //-Kommentar?</summary>
function BlankAfter(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
/// <summary>Name ohne Unit- bzw. Typvorsatz und ohne Typargumente: "A.TB&lt;T&gt;" ergibt "TB".</summary>
function BareName(const AText: string): string;

implementation

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDeclarationsSharedText = (AndWord);

const
  cTexts: array[TDeclarationsSharedText] of TAtlasText = (
    (De: ' und '; En: ' and '));

{$SCOPEDENUMS OFF}

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(ATokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := mLow;
end;

/// <summary>Steht vor APosition in ihrer Zeile nur Leerraum?</summary>
function BlankBefore(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
begin
  Result := (APosition.Line < Length(ALines)) and (Trim(Copy(ALines[APosition.Line], 1, APosition.Character)) = '');
end;

/// <summary>Steht hinter APosition in ihrer Zeile nur Leerraum oder ein //-Kommentar?</summary>
function BlankAfter(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
var
  mRest: string;
begin
  Result := False;
  if APosition.Line >= Length(ALines) then
  begin
    Exit;
  end;
  mRest := Trim(Copy(ALines[APosition.Line], APosition.Character + 1, MaxInt));
  Result := (mRest = '') or mRest.StartsWith('//');
end;

/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AItems) do
  begin
    if mIndex = 0 then
    begin
      Result := AItems[mIndex];
    end
    else if mIndex = High(AItems) then
    begin
      Result := Result + cTexts[TDeclarationsSharedText.AndWord].Text + AItems[mIndex];
    end
    else
    begin
      Result := Result + ', ' + AItems[mIndex];
    end;
  end;
end;

/// <summary>Name ohne Unit- bzw. Typvorsatz und ohne Typargumente: "A.TB&lt;T&gt;" ergibt "TB".</summary>
function BareName(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Declarations.Shared', cTexts);

end.
