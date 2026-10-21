unit Atlas.Common.Lsp.ConditionalSymbols;

// Bedingte Symbole in Direktiven (#102, Teil 2): Hover über {$IFDEF X},
// {$IFNDEF X}, {$IF Defined(X)}, {$ELSEIF Defined(X)}, {$DEFINE X} und
// {$UNDEF X} nennt, ob X an dieser Stelle definiert ist und woher es kommt:
//   - Projekt bzw. Konfiguration und Plattform aus der .dproj (DefineOrigins),
//   - Projektoptionen der IDE (Symbole ohne Eintrag in der .dproj, #615),
//   - Compiler-Vorgabe für Plattform und Version (MSWINDOWS, WIN64, VER370 …),
//   - {$DEFINE}/{$UNDEF} mit Datei und Zeile, auch aus Include-Dateien.
// Der Zustand folgt dem Präprozessor bis zur Direktive: Symbole des Projekts,
// dann alle wirksamen $DEFINE/$UNDEF davor (Include-Dateien zählen an der
// Stelle ihrer $I-Direktive).
// Die Vervollständigung nach {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF und in
// Defined( bietet die Symbole mit Herkunft an: Projekt und Compiler, dann
// $DEFINE der Datei und ihrer Includes, dann in der Datei benutzte Namen und
// Compiler-Symbole anderer Plattformen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor;

type
  /// <summary>Herkunft eines Symbols, das schon vor der ersten Zeile gilt.</summary>
  TSymbolSource = record
    Name: string;
    /// <summary>Etwa "Konfiguration Debug (.dproj)" oder "Compiler-Vorgabe (Plattform Win64)".</summary>
    Origin: string;
  end;

  /// <summary>Was zu den Symbolen einer Datei bekannt ist; liefert die Composition je Dokument.</summary>
  TConditionalContext = record
    /// <summary>Vervollständigung in Direktiven (directives.completion).</summary>
    CompletionEnabled: Boolean;
    /// <summary>Hover über Direktiven und Symbolen (directives.hover).</summary>
    HoverEnabled: Boolean;
    /// <summary>Gibt es ein Projekt mit Symbolen? Sonst ist der Zustand nur aus der Datei bekannt.</summary>
    HasDefines: Boolean;
    /// <summary>Symbole am Dateianfang: Projekt und Compiler.</summary>
    Defines: TArray<string>;
    Sources: TArray<TSymbolSource>;
    FileName: string;
    ResolveInclude: TIncludeResolver;
    /// <summary>Beides eingeschaltet, ohne Projekt.</summary>
    class function Default: TConditionalContext; static;
  end;

  /// <summary>Kontext je Dokument AUri.</summary>
  TConditionalContextFunc = reference to function(const AUri: string): TConditionalContext;

  /// <summary>Vorschlag für ein Symbol.</summary>
  TConditionalSymbol = record
    Name: string;
    /// <summary>Herkunft, etwa "Konfiguration Debug (.dproj)" oder "{$DEFINE} Zeile 12".</summary>
    Detail: string;
    /// <summary>Am Dateianfang bzw. nach der Datei definiert.</summary>
    Active: Boolean;
  end;

  TConditionalSymbols = class
  public
    /// <summary>Herkunft der Symbole am Dateianfang: AProjectDefines mit AOrigins aus der .dproj (sonst
    /// "Projektoptionen der IDE"), APredefined als Compiler-Vorgabe für APlatform.</summary>
    class function SourcesOf(const AProjectDefines: TArray<string>; const AOrigins: TArray<TPair<string, string>>;
      const APredefined: TArray<string>; const APlatform: string): TArray<TSymbolSource>; static;
    /// <summary>Symbol der Direktive an APosition und der Name der Direktive (IFDEF, IFNDEF, IF, ELSEIF, DEFINE,
    /// UNDEF); bei {$IF} das Defined(X) unter dem Cursor bzw. das einzige. AStart: Anfang der Direktive.</summary>
    class function SymbolAt(const AText: string; const APosition: TTextPosition; out AName, ADirective: string;
      out AStart: TTextPosition): Boolean; static;
    /// <summary>Markdown für den Hover über dem Symbol einer Direktive an APosition; False ohne Symbol.</summary>
    class function Hover(const AText: string; const APosition: TTextPosition; const AContext: TConditionalContext;
      out AMarkdown: string): Boolean; static;
    /// <summary>Steht vor dem Cursor die Stelle eines Symbols: {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF oder
    /// Defined( in {$IF bzw. {$ELSEIF? APrefix: schon getippter Teil des Namens.</summary>
    class function IsSymbolContext(const ALineBefore: string; out APrefix: string): Boolean; static;
    /// <summary>Alle bekannten Symbole mit Herkunft, ohne Doppelte, in der Reihenfolge oben.</summary>
    class function Candidates(const AText: string; const AContext: TConditionalContext): TArray<TConditionalSymbol>;
      static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Defines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.Uris;

const
  /// <summary>Plattformen für die Compiler-Symbole, die hier nicht gelten.</summary>
  OtherPlatforms: array[0..8] of string = ('Win32', 'Win64', 'Linux64', 'OSX64', 'OSXARM64', 'Android',
    'Android64', 'iOSDevice64', 'iOSSimARM64');

{ TConditionalContext }

class function TConditionalContext.Default: TConditionalContext;
begin
  Result := System.Default(TConditionalContext);
  Result.CompletionEnabled := True;
  Result.HoverEnabled := True;
end;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ TConditionalSymbols }

class function TConditionalSymbols.SourcesOf(const AProjectDefines: TArray<string>;
  const AOrigins: TArray<TPair<string, string>>; const APredefined: TArray<string>;
  const APlatform: string): TArray<TSymbolSource>;
var
  Source: TSymbolSource;
  Origin: TPair<string, string>;
  Name: string;
begin
  Result := nil;
  for Name in AProjectDefines do
  begin
    Source.Name := UpperCase(Name);
    Source.Origin := 'Projektoptionen der IDE';
    for Origin in AOrigins do
      if SameText(Origin.Key, Name) then
      begin
        Source.Origin := Origin.Value + ' (.dproj)';
        Break;
      end;
    Result := Result + [Source];
  end;
  for Name in APredefined do
  begin
    Source.Name := UpperCase(Name);
    Source.Origin := 'Compiler-Vorgabe';
    if APlatform <> '' then
      Source.Origin := Source.Origin + ' (Plattform ' + APlatform + ')';
    Result := Result + [Source];
  end;
end;

/// <summary>Direktive an APosition; False, wenn dort keine steht.</summary>
function DirectiveAt(const AText: string; const APosition: TTextPosition; out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in TPascalLexer.Tokenize(AText) do
    if (Token.Kind = TPascalTokenKind.Directive) and not Before(APosition, Token.StartPos) and
      Before(APosition, Token.EndPos) then
    begin
      AToken := Token;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Inhalt nach "{$" bzw. "(*$" ohne schließende Klammer; AOffset = Index des Inhalts im Token.</summary>
function DirectiveBody(const AText: string; out AOffset: Integer): string;
begin
  AOffset := 3;
  if StartsStr('(*$', AText) then
    AOffset := 4;
  Result := Copy(AText, AOffset, MaxInt);
  if EndsStr('*)', Result) then
    SetLength(Result, Length(Result) - 2)
  else if EndsStr('}', Result) then
    SetLength(Result, Length(Result) - 1);
end;

/// <summary>Namen in Defined(…) im Ausdruck AText: Anfang (1-basiert) und Name.</summary>
function DefinedNames(const AText: string): TArray<TPair<Integer, string>>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Index := Pos('DEFINED', UpperCase(AText));
  while Index > 0 do
  begin
    Start := Index + Length('DEFINED');
    while (Start <= Length(AText)) and (AText[Start] = ' ') do
      Inc(Start);
    if (Start <= Length(AText)) and (AText[Start] = '(') and ((Index = 1) or not IsNameChar(AText[Index - 1])) then
    begin
      Inc(Start);
      while (Start <= Length(AText)) and (AText[Start] = ' ') do
        Inc(Start);
      Index := Start;
      while (Index <= Length(AText)) and IsNameChar(AText[Index]) do
        Inc(Index);
      if Index > Start then
        Result := Result + [TPair<Integer, string>.Create(Start, Copy(AText, Start, Index - Start))];
    end;
    Index := PosEx('DEFINED', UpperCase(AText), Index + 1);
  end;
end;

/// <summary>Name der Direktive und Symbole darin; AStarts sind 1-basiert im Token.</summary>
procedure SplitSymbols(const AToken: string; out ADirective: string; out ANames: TArray<string>;
  out AStarts: TArray<Integer>);
var
  Body: string;
  Offset, Index, Start: Integer;
  Found: TPair<Integer, string>;
begin
  ANames := nil;
  AStarts := nil;
  Body := DirectiveBody(AToken, Offset);
  Index := 1;
  while (Index <= Length(Body)) and IsNameChar(Body[Index]) do
    Inc(Index);
  ADirective := UpperCase(Copy(Body, 1, Index - 1));
  if MatchStr(ADirective, ['IFDEF', 'IFNDEF', 'DEFINE', 'UNDEF']) then
  begin
    while (Index <= Length(Body)) and (Body[Index] = ' ') do
      Inc(Index);
    Start := Index;
    while (Index <= Length(Body)) and IsNameChar(Body[Index]) do
      Inc(Index);
    if Index > Start then
    begin
      ANames := [Copy(Body, Start, Index - Start)];
      AStarts := [Start + Offset - 1];
    end;
  end
  else if MatchStr(ADirective, ['IF', 'ELSEIF']) then
    for Found in DefinedNames(Copy(Body, Index, MaxInt)) do
    begin
      ANames := ANames + [Found.Value];
      AStarts := AStarts + [Found.Key + Index - 1 + Offset - 1];
    end;
end;

class function TConditionalSymbols.SymbolAt(const AText: string; const APosition: TTextPosition;
  out AName, ADirective: string; out AStart: TTextPosition): Boolean;
var
  Token: TPascalToken;
  Names: TArray<string>;
  Starts: TArray<Integer>;
  Index, Column: Integer;
begin
  AName := '';
  ADirective := '';
  AStart := APosition;
  if not DirectiveAt(AText, APosition, Token) then
    Exit(False);
  AStart := Token.StartPos;
  SplitSymbols(Token.Text, ADirective, Names, Starts);
  if Names = nil then
    Exit(False);
  if Length(Names) = 1 then
    AName := Names[0]
  else if Token.StartPos.Line = APosition.Line then
  begin
    // Mehrere Defined(…): das unter dem Cursor (1-basiert im Token).
    Column := APosition.Character - Token.StartPos.Character + 1;
    for Index := 0 to High(Names) do
      if (Column >= Starts[Index]) and (Column <= Starts[Index] + Length(Names[Index])) then
        AName := Names[Index];
  end;
  AName := UpperCase(AName);
  Result := AName <> '';
end;

function OptionsFor(const AContext: TConditionalContext): TPreprocessorOptions;
begin
  Result := TPreprocessorOptions.Default;
  Result.Defines := AContext.Defines;
  Result.CompilerVersion := TPascalPreprocessor.CompilerVersionFromDefines(AContext.Defines);
  Result.FileName := AContext.FileName;
  Result.ResolveInclude := AContext.ResolveInclude;
end;

/// <summary>"in Zeile 12" bzw. "in [Defs.inc](file:///…), Zeile 3".</summary>
function SiteText(const AProcessed: TPreprocessorResult; const ASite: TDefineSite): string;
var
  FileName: string;
begin
  if ASite.FileIndex = 0 then
    Exit(Format('in Zeile %d', [ASite.Range.StartPos.Line + 1]));
  FileName := AProcessed.Files[ASite.FileIndex];
  Result := Format('in [%s](%s), Zeile %d', [ExtractFileName(FileName), TDocumentUris.FromPath(FileName),
    ASite.Range.StartPos.Line + 1]);
end;

function InInactiveRange(const AProcessed: TPreprocessorResult; const APosition: TTextPosition): Boolean;
var
  Inactive: TInactiveRange;
begin
  for Inactive in AProcessed.InactiveRanges do
    if (Inactive.FileIndex = 0) and not Before(APosition, Inactive.Range.StartPos) and
      Before(APosition, Inactive.Range.EndPos) then
      Exit(True);
  Result := False;
end;

class function TConditionalSymbols.Hover(const AText: string; const APosition: TTextPosition;
  const AContext: TConditionalContext; out AMarkdown: string): Boolean;
var
  Name, Directive, State, Origin: string;
  Start: TTextPosition;
  Processed: TPreprocessorResult;
  Site, Last: TDefineSite;
  HasSite, Defined: Boolean;
  Source: TSymbolSource;
begin
  AMarkdown := '';
  if not AContext.HoverEnabled or not SymbolAt(AText, APosition, Name, Directive, Start) then
    Exit(False);
  Processed := TPascalPreprocessor.Process(AText, OptionsFor(AContext));
  Defined := IndexText(Name, AContext.Defines) >= 0;
  HasSite := False;
  Last := Default(TDefineSite);
  // Wirksame $DEFINE/$UNDEF vor der Direktive, Include-Dateien an der Stelle ihrer $I-Direktive.
  for Site in Processed.DefineSites do
    if SameText(Site.Name, Name) and Before(Site.RootPos, Start) then
    begin
      Defined := not Site.Undefine;
      Last := Site;
      HasSite := True;
    end;
  if HasSite then
  begin
    if Last.Undefine then
      Origin := Format('aufgehoben mit {$UNDEF %s} %s', [Name, SiteText(Processed, Last)])
    else
      Origin := Format('definiert mit {$DEFINE %s} %s', [Name, SiteText(Processed, Last)]);
  end
  else
  begin
    Origin := '';
    for Source in AContext.Sources do
      if SameText(Source.Name, Name) then
      begin
        Origin := 'definiert in ' + Source.Origin;
        if StartsText('Compiler', Source.Origin) then
          Origin := Source.Origin;
        Break;
      end;
    if (Origin = '') and not Defined and AContext.HasDefines then
      Origin := 'weder im Projekt noch vom Compiler noch mit {$DEFINE} davor gesetzt'
    else if (Origin = '') and not AContext.HasDefines then
      Origin := 'kein Projekt geladen, nur die Datei ausgewertet';
  end;
  if Defined then
    State := 'aktiv'
  else
    State := 'nicht definiert';
  AMarkdown := Format('**%s**: %s', [Name, State]);
  if Origin <> '' then
    AMarkdown := AMarkdown + ', ' + Origin;
  if Directive = 'DEFINE' then
    AMarkdown := AMarkdown + #10#10 + Format('Diese Direktive definiert **%s** ab hier.', [Name])
  else if Directive = 'UNDEF' then
    AMarkdown := AMarkdown + #10#10 + Format('Diese Direktive hebt **%s** ab hier auf.', [Name]);
  if InInactiveRange(Processed, Start) then
    AMarkdown := AMarkdown + #10#10 + 'Die Direktive liegt in einem inaktiven Zweig und wirkt nicht.';
  Result := True;
end;

class function TConditionalSymbols.IsSymbolContext(const ALineBefore: string; out APrefix: string): Boolean;
var
  Open, Index, Offset: Integer;
  Body, Directive, Rest: string;
begin
  APrefix := '';
  Open := 0;
  while PosEx('{$', ALineBefore, Open + 1) > 0 do
    Open := PosEx('{$', ALineBefore, Open + 1);
  if (Open = 0) or (PosEx('}', ALineBefore, Open) > 0) then
    Exit(False);
  Body := DirectiveBody(Copy(ALineBefore, Open, MaxInt), Offset);
  // Getippten Teil des Namens abtrennen.
  Index := Length(Body);
  while (Index > 0) and IsNameChar(Body[Index]) do
    Dec(Index);
  APrefix := Copy(Body, Index + 1, MaxInt);
  Rest := Copy(Body, 1, Index);
  Index := 1;
  while (Index <= Length(Rest)) and IsNameChar(Rest[Index]) do
    Inc(Index);
  Directive := UpperCase(Copy(Rest, 1, Index - 1));
  if MatchStr(Directive, ['IFDEF', 'IFNDEF', 'DEFINE', 'UNDEF']) then
    Exit(Trim(Copy(Rest, Index, MaxInt)) = '');
  // {$IF Defined( bzw. {$ELSEIF … or Defined(
  Result := MatchStr(Directive, ['IF', 'ELSEIF']) and EndsText('DEFINED(', StringReplace(UpperCase(TrimRight(Rest)),
    ' ', '', [rfReplaceAll]));
end;

class function TConditionalSymbols.Candidates(const AText: string;
  const AContext: TConditionalContext): TArray<TConditionalSymbol>;
var
  Seen: TDictionary<string, Boolean>;
  Found: TList<TConditionalSymbol>;
  Processed: TPreprocessorResult;
  Source: TSymbolSource;
  Site: TDefineSite;
  Token: TPascalToken;
  Directive, Name, Platform: string;
  Names: TArray<string>;
  Starts: TArray<Integer>;

  procedure Add(const AName, ADetail: string; AActive: Boolean);
  var
    Item: TConditionalSymbol;
  begin
    if (AName = '') or Seen.ContainsKey(UpperCase(AName)) then
      Exit;
    Seen.Add(UpperCase(AName), True);
    Item.Name := UpperCase(AName);
    Item.Detail := ADetail;
    Item.Active := AActive;
    Found.Add(Item);
  end;

begin
  Seen := TDictionary<string, Boolean>.Create;
  Found := TList<TConditionalSymbol>.Create;
  try
    for Source in AContext.Sources do
      Add(Source.Name, Source.Origin, True);
    Processed := TPascalPreprocessor.Process(AText, OptionsFor(AContext));
    for Site in Processed.DefineSites do
      if not Site.Undefine then
        Add(Site.Name, '{$DEFINE} ' + StringReplace(SiteText(Processed, Site), 'in ', '', []),
          IndexText(Site.Name, Processed.Defines) >= 0);
    for Token in TPascalLexer.Tokenize(AText) do
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        SplitSymbols(Token.Text, Directive, Names, Starts);
        for Name in Names do
          Add(Name, Format('in der Datei verwendet (Zeile %d)', [Token.StartPos.Line + 1]),
            IndexText(Name, Processed.Defines) >= 0);
      end;
    for Platform in OtherPlatforms do
      for Name in TTextDefines.Predefined(Platform, 0) do
        Add(Name, 'Compiler-Vorgabe auf ' + Platform, False);
    Result := Found.ToArray;
  finally
    Found.Free;
    Seen.Free;
  end;
end;

end.
