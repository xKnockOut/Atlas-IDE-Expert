unit BDLsp.Common.Editing.UnitFiles;

// Dateioperationen auf Units (#181), ohne Protokollbezug.
//
// - Gerüst einer neuen Unit mit dem Namen aus dem Dateinamen.
// - Umbenennen: Kopfzeile (unit/program/library/package), Einträge in uses,
//   contains und requires samt "in 'Pfad'" sowie DCCReference-Einträge
//   einer .dproj.
// - Verweise auf eine Unit in uses, contains und requires, z. B. für
//   gelöschte Dateien.
// Verglichen wird ohne Rücksicht auf Groß- und Kleinschreibung; neue Namen
// werden so eingesetzt, wie sie übergeben werden.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Rules.Contract;

type
  TUnitFiles = class
  public
    /// <summary>Unit-Name aus einem Pfad: Dateiname ohne letzte Erweiterung, z. B.
    /// C:\App\Data.Model.pas -> Data.Model.</summary>
    class function UnitNameOf(const AFileName: string): string; static;
    /// <summary>True für .pas-Dateien.</summary>
    class function IsUnitFile(const AFileName: string): Boolean; static;
    /// <summary>Gerüst einer leeren Unit.</summary>
    class function Skeleton(const AUnitName, ALineBreak: string): string; static;
    /// <summary>Name aus der Kopfzeile und dessen Bereich; False ohne Kopf.
    /// AKeyword ist unit, program, library oder package in Kleinbuchstaben.</summary>
    class function Header(const ATokens: TArray<TPascalToken>; out AName: string; out ARange: TTextRange;
      out AKeyword: string): Boolean; static;
    /// <summary>Bereiche der Einträge von AUnitName in uses, contains und requires.</summary>
    class function References(const ATokens: TArray<TPascalToken>; const AUnitName: string): TArray<TTextRange>; static;
    /// <summary>Edits, die AOldName in Kopf, uses und "in 'Pfad'" durch ANewName ersetzen.</summary>
    class function RenameEdits(const ATokens: TArray<TPascalToken>; const AOldName, ANewName: string): TArray<TRuleEdit>; static;
    /// <summary>Edits für eine .dproj: DCCReference-Einträge, deren Dateiname AOldFile ist, auf ANewFile ändern
    /// (nur der Dateiname, der Ordner bleibt).</summary>
    class function ProjectFileEdits(const AText, AOldFile, ANewFile: string): TArray<TRuleEdit>; static;
  end;

implementation

uses
  System.StrUtils;

type
  /// <summary>Ein Eintrag einer uses-Liste: Namensbereich und optional der Pfad-String.</summary>
  TUsesEntry = record
    Name: string;
    First, Last: Integer;
    PathToken: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function FileNamePart(const APath: string): string;
var
  Index: Integer;
begin
  Index := Length(APath);
  while (Index > 0) and not CharInSet(APath[Index], ['/', '\']) do
    Dec(Index);
  Result := Copy(APath, Index + 1, MaxInt);
end;

function WithoutExtension(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := LastDelimiter('.', AFileName);
  if Index > 1 then
    Result := Copy(AFileName, 1, Index - 1)
  else
    Result := AFileName;
end;

function Extension(const AFileName: string): string;
var
  Index: Integer;
begin
  Index := LastDelimiter('.', AFileName);
  if Index > 0 then
    Result := Copy(AFileName, Index, MaxInt)
  else
    Result := '';
end;

/// <summary>Index des vorigen Tokens ohne Trivia; -1 am Anfang.</summary>
function PreviousIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>True, wenn an AIndex eine uses-, contains- oder requires-Liste beginnt.</summary>
function IsListStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Previous: Integer;
begin
  if ATokens[AIndex].IsKeyword('uses') then
    Exit(True);
  // contains und requires sind keine reservierten Wörter, nur am Anweisungsanfang gemeint.
  if not ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (SameText(ATokens[AIndex].Text, 'contains') or SameText(ATokens[AIndex].Text, 'requires'))) then
    Exit(False);
  Previous := PreviousIndex(ATokens, AIndex);
  Result := (Previous >= 0) and ATokens[Previous].IsSymbol(';');
end;

/// <summary>Alle Einträge aller uses-, contains- und requires-Listen.</summary>
function UsesEntries(const ATokens: TArray<TPascalToken>): TArray<TUsesEntry>;
var
  Index: Integer;
  Entry: TUsesEntry;
  AfterIn: Boolean;

  procedure Flush;
  begin
    if Entry.Name <> '' then
      Result := Result + [Entry];
    Entry.Name := '';
    Entry.First := -1;
    Entry.Last := -1;
    Entry.PathToken := -1;
    AfterIn := False;
  end;

begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if IsListStart(ATokens, Index) then
    begin
      Entry.Name := '';
      Flush;
      Inc(Index);
      while Index <= High(ATokens) do
      begin
        if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
        begin
          Flush;
          if ATokens[Index].IsSymbol(';') then
            Break;
        end
        else if ATokens[Index].IsKeyword('in') then
          AfterIn := True
        else if AfterIn and (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) then
          Entry.PathToken := Index
        else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
          ATokens[Index].IsSymbol('.')) then
        begin
          if Entry.First < 0 then
            Entry.First := Index;
          Entry.Last := Index;
          Entry.Name := Entry.Name + ATokens[Index].Text;
        end;
        Inc(Index);
      end;
    end;
    Inc(Index);
  end;
end;

function TokenRange(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Position zu einem Offset ab 0; Zeilenwechsel LF, CRLF oder CR.</summary>
function PositionAt(const AText: string; AOffset: Integer): TTextPosition;
var
  Index, Line, LineStart: Integer;
begin
  Line := 0;
  LineStart := 0;
  Index := 0;
  while Index < AOffset do
  begin
    // Bei CRLF zählt erst das LF als Zeilenwechsel.
    if (AText[Index + 1] = #10) or ((AText[Index + 1] = #13) and
      not ((Index + 1 < Length(AText)) and (AText[Index + 2] = #10))) then
    begin
      Inc(Line);
      LineStart := Index + 1;
    end;
    Inc(Index);
  end;
  Result := TTextPosition.Create(Line, AOffset - LineStart);
end;

{ TUnitFiles }

class function TUnitFiles.UnitNameOf(const AFileName: string): string;
begin
  Result := WithoutExtension(FileNamePart(AFileName));
end;

class function TUnitFiles.IsUnitFile(const AFileName: string): Boolean;
begin
  Result := SameText(Extension(AFileName), '.pas');
end;

class function TUnitFiles.Skeleton(const AUnitName, ALineBreak: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak +
    'interface' + ALineBreak + ALineBreak +
    'implementation' + ALineBreak + ALineBreak +
    'end.' + ALineBreak;
end;

class function TUnitFiles.Header(const ATokens: TArray<TPascalToken>; out AName: string; out ARange: TTextRange;
  out AKeyword: string): Boolean;
var
  Index, First, Last: Integer;
begin
  AName := '';
  AKeyword := '';
  Index := 0;
  while (Index <= High(ATokens)) and IsTrivia(ATokens[Index]) do
    Inc(Index);
  if Index > High(ATokens) then
    Exit(False);
  if ATokens[Index].IsKeyword('unit') or ATokens[Index].IsKeyword('program') or
    ATokens[Index].IsKeyword('library') or ATokens[Index].IsKeyword('package') then
    AKeyword := LowerCase(ATokens[Index].Text)
  else if (ATokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[Index].Text, 'package') then
    AKeyword := 'package'
  else
    Exit(False);
  First := -1;
  Last := -1;
  Inc(Index);
  while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol(';') and
    ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.') or IsTrivia(ATokens[Index])) do
  begin
    if not IsTrivia(ATokens[Index]) then
    begin
      if First < 0 then
        First := Index;
      Last := Index;
      AName := AName + ATokens[Index].Text;
    end;
    Inc(Index);
  end;
  Result := First >= 0;
  if Result then
    ARange := TokenRange(ATokens, First, Last);
end;

class function TUnitFiles.References(const ATokens: TArray<TPascalToken>;
  const AUnitName: string): TArray<TTextRange>;
var
  Entry: TUsesEntry;
begin
  Result := nil;
  for Entry in UsesEntries(ATokens) do
    if SameText(Entry.Name, AUnitName) then
      Result := Result + [TokenRange(ATokens, Entry.First, Entry.Last)];
end;

class function TUnitFiles.RenameEdits(const ATokens: TArray<TPascalToken>;
  const AOldName, ANewName: string): TArray<TRuleEdit>;
var
  Name, Keyword, Path, OldFile: string;
  Range: TTextRange;
  Entry: TUsesEntry;
  Token: TPascalToken;
begin
  Result := nil;
  if Header(ATokens, Name, Range, Keyword) and SameText(Name, AOldName) then
    Result := Result + [TRuleEdit.Create(Range, ANewName)];
  for Entry in UsesEntries(ATokens) do
  begin
    if not SameText(Entry.Name, AOldName) then
      Continue;
    Result := Result + [TRuleEdit.Create(TokenRange(ATokens, Entry.First, Entry.Last), ANewName)];
    if Entry.PathToken < 0 then
      Continue;
    // 'Ordner\Alt.pas' -> 'Ordner\Neu.pas'; der Ordner bleibt.
    Token := ATokens[Entry.PathToken];
    Path := Copy(Token.Text, 2, Length(Token.Text) - 2);
    OldFile := FileNamePart(Path);
    if SameText(WithoutExtension(OldFile), AOldName) then
      Result := Result + [TRuleEdit.Create(TTextRange.Create(Token.StartPos, Token.EndPos),
        '''' + Copy(Path, 1, Length(Path) - Length(OldFile)) + ANewName + Extension(OldFile) + '''')];
  end;
end;

class function TUnitFiles.ProjectFileEdits(const AText, AOldFile, ANewFile: string): TArray<TRuleEdit>;
const
  Marker = '<DCCReference Include="';
var
  Start, ValueStart, ValueEnd, NameStart: Integer;
  Value, OldName, NewName, Lower: string;
begin
  Result := nil;
  Lower := LowerCase(AText);
  OldName := FileNamePart(AOldFile);
  NewName := FileNamePart(ANewFile);
  Start := Pos(LowerCase(Marker), Lower);
  while Start > 0 do
  begin
    ValueStart := Start + Length(Marker);
    ValueEnd := PosEx('"', AText, ValueStart);
    if ValueEnd = 0 then
      Break;
    Value := Copy(AText, ValueStart, ValueEnd - ValueStart);
    if SameText(FileNamePart(Value), OldName) then
    begin
      NameStart := ValueEnd - Length(OldName);
      // Offsets ab 0 für die Positionen.
      Result := Result + [TRuleEdit.Create(TTextRange.Create(PositionAt(AText, NameStart - 1),
        PositionAt(AText, ValueEnd - 1)), NewName)];
    end;
    Start := PosEx(LowerCase(Marker), Lower, ValueEnd);
  end;
end;

end.
