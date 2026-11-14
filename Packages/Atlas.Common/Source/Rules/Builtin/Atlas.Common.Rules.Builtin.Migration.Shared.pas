unit Atlas.Common.Rules.Builtin.Migration.Shared;

// Gemeinsames der Migrationsregeln (#112, #117; Gruppe „Migration“):
//   - Stellen in inaktiven Zweigen der bedingten Übersetzung (TRuleContext.InactiveRanges) meldet keine Regel.
//   - Plattformzweige: Code in {$IFDEF CPUX86}, {$IFDEF WIN32}, {$IF SizeOf(Pointer) = 4} usw. und in deren
//     {$ELSE}-Zweigen ist schon nach Plattform getrennt; die Win64-Regeln melden dort nichts.
//   - Ganzzahltypen fester Breite von 32 Bit (Integer, LongInt, Cardinal, DWORD …), die unter Win64 keinen Zeiger
//     fassen, und Typen in Zeigerbreite (THandle, HWND, WPARAM, LPARAM, LRESULT …).
//   - Delphi-Versionen: Win64 gibt es ab XE2 (BDS 9.0), string ist UTF-16 ab Delphi 2009 (BDS 6.0). Ist die
//     eingestellte Version älter, schweigen die Regeln.

interface

uses
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Plattformzweige und inaktive Bereiche einer geprüften Datei.</summary>
  TMigrationScope = class
  private
    FTokens: TArray<TPascalToken>;
    FGuarded: TArray<Boolean>;
    FInactive: TArray<TTextRange>;
    FLines: TLineTable;
    procedure BuildGuards;
  public
    constructor Create(const AContext: TRuleContext);
    /// <summary>Liegt APosition in einem inaktiven Zweig?</summary>
    function Inactive(const APosition: TTextPosition): Boolean;
    /// <summary>Steht das Token an APosition in einem Zweig, dessen Bedingung (oder eine umschließende) nach
    /// Plattform oder Zeigerbreite fragt?</summary>
    function PlatformGuarded(const APosition: TTextPosition): Boolean;
    /// <summary>Weder inaktiv noch nach Plattform getrennt.</summary>
    function Reportable(const APosition: TTextPosition): Boolean;
    /// <summary>Offset von APosition im geprüften Text (für TokenFrom).</summary>
    function OffsetOf(const APosition: TTextPosition): Integer;
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

  TMigrationTypes = record
  public const
    cWin64Version = '9.0';
    cUnicodeVersion = '6.0';
  public
    /// <summary>Fragt die Bedingung einer Direktive ({$IFDEF CPUX64}, {$IF Defined(WIN32) or …}) nach Plattform
    /// oder Zeigerbreite?</summary>
    class function IsPlatformCondition(const ADirective: string): Boolean; static;
    /// <summary>Ganzzahltyp fester Breite von 32 Bit (Integer, LongInt, Cardinal, LongWord, DWORD, UINT …).
    /// </summary>
    class function Is32BitInteger(const ATypeName: string): Boolean; static;
    /// <summary>Vorzeichenloser Typ aus Is32BitInteger (Cardinal, LongWord, DWORD …)?</summary>
    class function IsUnsigned32(const ATypeName: string): Boolean; static;
    /// <summary>Windows-Typ in Zeigerbreite: Handles (THandle, HWND, HDC …), WPARAM, LPARAM, LRESULT, *_PTR.
    /// NativeInt und NativeUInt gehören nicht dazu (meldet narrowing-assignment).</summary>
    class function IsPointerSizedAlias(const ATypeName: string): Boolean; static;
    /// <summary>Eingebauter UTF-16-Stringtyp: string, UnicodeString, WideString.</summary>
    class function IsUnicodeString(const ATypeName: string): Boolean; static;
    /// <summary>Zeiger auf UTF-16-Zeichen: PChar, PWideChar.</summary>
    class function IsWideCharPointer(const ATypeName: string): Boolean; static;
    /// <summary>Gibt es für ADelphiVersion (BDS-Nummer, '' = unbekannt) Win64?</summary>
    class function Win64Available(const ADelphiVersion: string): Boolean; static;
    /// <summary>Ist string für ADelphiVersion UTF-16?</summary>
    class function UnicodeAvailable(const ADelphiVersion: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.LanguageFeatures;

function ComparePosition(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

{ TMigrationScope }

constructor TMigrationScope.Create(const AContext: TRuleContext);
begin
  inherited Create;
  if AContext.Tree <> nil then
  begin
    FTokens := AContext.Tree.Tokens;
  end;
  FInactive := AContext.InactiveRanges;
  FLines := TLineTable.Build(AContext.Text);
  BuildGuards;
end;

procedure TMigrationScope.BuildGuards;
var
  mStack: TArray<Boolean>;
  mIndex: Integer;
  mName: string;
  mGuarded, mEntry: Boolean;
begin
  mStack := nil;
  SetLength(FGuarded, Length(FTokens));
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      mName := TPascalLexer.DirectiveName(FTokens[mIndex].Text);
      if MatchStr(mName, ['IF', 'IFDEF', 'IFNDEF', 'IFOPT']) then
      begin
        mStack := mStack + [TMigrationTypes.IsPlatformCondition(FTokens[mIndex].Text)];
      end
      else if (mName = 'ELSEIF') and (mStack <> nil) then
      begin
        mStack[High(mStack)] := mStack[High(mStack)] or TMigrationTypes.IsPlatformCondition(FTokens[mIndex].Text);
      end
      else if MatchStr(mName, ['ENDIF', 'IFEND']) and (mStack <> nil) then
      begin
        SetLength(mStack, Length(mStack) - 1);
      end;
    end;
    mGuarded := False;
    for mEntry in mStack do
    begin
      mGuarded := mGuarded or mEntry;
    end;
    FGuarded[mIndex] := mGuarded;
  end;
end;

function TMigrationScope.OffsetOf(const APosition: TTextPosition): Integer;
begin
  Result := FLines.OffsetAt(APosition);
end;

function TMigrationScope.Inactive(const APosition: TTextPosition): Boolean;
var
  mRange: TTextRange;
begin
  Result := False;
  for mRange in FInactive do
  begin
    if (ComparePosition(mRange.StartPos, APosition) <= 0) and (ComparePosition(APosition, mRange.EndPos) < 0) then
    begin
      Exit(True);
    end;
  end;
end;

function TMigrationScope.PlatformGuarded(const APosition: TTextPosition): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TokenFrom(FTokens, OffsetOf(APosition));
  Result := (mIndex <= High(FGuarded)) and FGuarded[mIndex];
end;

function TMigrationScope.Reportable(const APosition: TTextPosition): Boolean;
begin
  Result := not Inactive(APosition) and not PlatformGuarded(APosition);
end;

{ TMigrationTypes }

const
  // Wortteile von Symbolen, die eine Plattform, einen Prozessor oder eine Bitbreite nennen.
  cPlatformWordParts: array[0..4] of string = ('ASM', 'X86', 'X64', '64BIT', '32BIT');

/// <summary>Nennt das groß geschriebene Wort AWord eine Plattform, einen Prozessor oder eine Bitbreite?</summary>
function IsPlatformWord(const AWord: string): Boolean;
var
  mPart: string;
begin
  Result := StartsStr('CPU', AWord) or MatchStr(AWord, ['WIN32', 'WIN64', 'PUREPASCAL', 'LINUX64', 'OSX64']);
  for mPart in cPlatformWordParts do
  begin
    Result := Result or ContainsStr(AWord, mPart);
  end;
end;

class function TMigrationTypes.IsPlatformCondition(const ADirective: string): Boolean;
var
  mText, mWord: string;
  mIndex, mStart: Integer;
begin
  Result := False;
  mText := UpperCase(ADirective);
  if ContainsStr(StringReplace(mText, ' ', '', [rfReplaceAll]), 'SIZEOF(POINTER)') or
    ContainsStr(StringReplace(mText, ' ', '', [rfReplaceAll]), 'SIZEOF(NATIVEINT)') then
  begin
    Exit(True);
  end;
  mIndex := 1;
  while mIndex <= Length(mText) do
  begin
    if CharInSet(mText[mIndex], ['A'..'Z', '0'..'9', '_']) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['A'..'Z', '0'..'9', '_']) do
      begin
        Inc(mIndex);
      end;
      mWord := Copy(mText, mStart, mIndex - mStart);
      if IsPlatformWord(mWord) then
      begin
        Exit(True);
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

class function TMigrationTypes.Is32BitInteger(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['Integer', 'LongInt', 'Int32', 'LONG']) or IsUnsigned32(ATypeName);
end;

class function TMigrationTypes.IsUnsigned32(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['Cardinal', 'LongWord', 'DWORD', 'UInt32', 'UINT', 'ULONG']);
end;

class function TMigrationTypes.IsPointerSizedAlias(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['THandle', 'HWND', 'HDC', 'HINST', 'HMODULE', 'HICON', 'HBITMAP', 'HBRUSH',
    'HFONT', 'HPEN', 'HMENU', 'HKEY', 'HGLOBAL', 'HRGN', 'HCURSOR', 'HPALETTE', 'HMONITOR', 'HGDIOBJ', 'HRSRC',
    'HHOOK', 'HINSTANCE', 'WPARAM', 'LPARAM', 'LRESULT', 'UINT_PTR', 'INT_PTR', 'LONG_PTR', 'ULONG_PTR',
    'DWORD_PTR', 'SIZE_T', 'IntPtr', 'UIntPtr']);
end;

class function TMigrationTypes.IsUnicodeString(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['string', 'UnicodeString', 'WideString']);
end;

class function TMigrationTypes.IsWideCharPointer(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['PChar', 'PWideChar']);
end;

class function TMigrationTypes.Win64Available(const ADelphiVersion: string): Boolean;
var
  mVersion: Integer;
begin
  mVersion := TLanguageFeatures.ParseVersion(ADelphiVersion);
  Result := (mVersion <= 0) or (mVersion >= TLanguageFeatures.ParseVersion(cWin64Version));
end;

class function TMigrationTypes.UnicodeAvailable(const ADelphiVersion: string): Boolean;
var
  mVersion: Integer;
begin
  mVersion := TLanguageFeatures.ParseVersion(ADelphiVersion);
  Result := (mVersion <= 0) or (mVersion >= TLanguageFeatures.ParseVersion(cUnicodeVersion));
end;

end.
