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
// Hover über {$IF}, {$ELSEIF} und {$IFOPT} nennt den Wert der Bedingung und
// ihre Teilwerte mit Herkunft (SizeOf nach Zielplattform, RTLVersion111 nach
// Delphi-Version, Declared aus dem Index, Schalter aus der .dproj oder einem
// lokalen {$R-} davor); {$PUSHOPT}/{$POPOPT} nennen ihr Gegenstück (#847).
// Stammt das Symbol aus einer Include-Datei (#860), nennt der Hover dazu
// Zielplattform und Konfiguration des Projekts: „Projekt: Win64 · Debug“.

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
    /// <summary>Aktive Konfiguration (Debug, Release) für die Herkunft von Schaltern (#847); '' ohne Projekt.
    /// </summary>
    Config: string;
    /// <summary>Zielplattform des Projekts (Win32, Win64 …, #860); '' ohne Projekt.</summary>
    Platform: string;
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
    /// <summary>Markdown für den Hover über {$IF}, {$ELSEIF}, {$IFOPT}, {$PUSHOPT} oder {$POPOPT} an APosition:
    /// Wert der Bedingung mit Teilwerten und Herkunft (#847); False bei anderen Stellen.</summary>
    class function ConditionHover(const AText: string; const APosition: TTextPosition;
      const AContext: TConditionalContext; out AMarkdown: string): Boolean; static;
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
    // Schalterstände für $IFOPT ("$R+", #847) sind keine Symbole.
    if TPascalPreprocessor.IsSwitchEntry(Name) then
    begin
      Continue;
    end;
    Source.Name := UpperCase(Name);
    Source.Origin := 'Projektoptionen der IDE';
    for Origin in AOrigins do
    begin
      if SameText(Origin.Key, Name) then
      begin
        Source.Origin := Origin.Value + ' (.dproj)';
        Break;
      end;
    end;
    Result := Result + [Source];
  end;
  for Name in APredefined do
  begin
    Source.Name := UpperCase(Name);
    Source.Origin := 'Compiler-Vorgabe';
    if APlatform <> '' then
    begin
      Source.Origin := Source.Origin + ' (Plattform ' + APlatform + ')';
    end;
    Result := Result + [Source];
  end;
end;

/// <summary>Direktive an APosition; False, wenn dort keine steht.</summary>
function DirectiveAt(const AText: string; const APosition: TTextPosition; out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if (Token.Kind = TPascalTokenKind.Directive) and not Before(APosition, Token.StartPos) and
      Before(APosition, Token.EndPos) then
    begin
      AToken := Token;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Inhalt nach "{$" bzw. "(*$" ohne schließende Klammer; AOffset = Index des Inhalts im Token.</summary>
function DirectiveBody(const AText: string; out AOffset: Integer): string;
begin
  AOffset := 3;
  if StartsStr('(*$', AText) then
  begin
    AOffset := 4;
  end;
  Result := Copy(AText, AOffset, MaxInt);
  if EndsStr('*)', Result) then
  begin
    SetLength(Result, Length(Result) - 2);
  end
  else if EndsStr('}', Result) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

function SkipSpaces(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] = ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Name in "Defined(Name)" zum Wort Defined bei AKeyword: Anfang AStart, Ende AEnd (dahinter). AEnd
/// bleibt AKeyword, wenn keine Klammer folgt; False ohne Namen.</summary>
function DefinedArgument(const AText: string; AKeyword: Integer; out AStart, AEnd: Integer): Boolean;
var
  mOpen: Integer;
begin
  AStart := 0;
  AEnd := AKeyword;
  mOpen := SkipSpaces(AText, AKeyword + Length('DEFINED'));
  if (mOpen > Length(AText)) or (AText[mOpen] <> '(') or ((AKeyword > 1) and IsNameChar(AText[AKeyword - 1])) then
  begin
    Exit(False);
  end;
  AStart := SkipSpaces(AText, mOpen + 1);
  AEnd := AStart;
  while (AEnd <= Length(AText)) and IsNameChar(AText[AEnd]) do
  begin
    Inc(AEnd);
  end;
  Result := AEnd > AStart;
end;

/// <summary>Namen in Defined(…) im Ausdruck AText: Anfang (1-basiert) und Name.</summary>
function DefinedNames(const AText: string): TArray<TPair<Integer, string>>;
var
  mUpper: string;
  mIndex, mStart, mEnd: Integer;
begin
  Result := nil;
  mUpper := UpperCase(AText);
  mIndex := Pos('DEFINED', mUpper);
  while mIndex > 0 do
  begin
    if DefinedArgument(AText, mIndex, mStart, mEnd) then
    begin
      Result := Result + [TPair<Integer, string>.Create(mStart, Copy(AText, mStart, mEnd - mStart))];
    end;
    mIndex := PosEx('DEFINED', mUpper, mEnd + 1);
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
  begin
    Inc(Index);
  end;
  ADirective := UpperCase(Copy(Body, 1, Index - 1));
  if MatchStr(ADirective, ['IFDEF', 'IFNDEF', 'DEFINE', 'UNDEF']) then
  begin
    while (Index <= Length(Body)) and (Body[Index] = ' ') do
    begin
      Inc(Index);
    end;
    Start := Index;
    while (Index <= Length(Body)) and IsNameChar(Body[Index]) do
    begin
      Inc(Index);
    end;
    if Index > Start then
    begin
      ANames := [Copy(Body, Start, Index - Start)];
      AStarts := [Start + Offset - 1];
    end;
  end
  else if MatchStr(ADirective, ['IF', 'ELSEIF']) then
  begin
    for Found in DefinedNames(Copy(Body, Index, MaxInt)) do
    begin
      ANames := ANames + [Found.Value];
      AStarts := AStarts + [Found.Key + Index - 1 + Offset - 1];
    end;
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
  begin
    Exit(False);
  end;
  AStart := Token.StartPos;
  SplitSymbols(Token.Text, ADirective, Names, Starts);
  if Names = nil then
  begin
    Exit(False);
  end;
  if Length(Names) = 1 then
  begin
    AName := Names[0];
  end
  else if Token.StartPos.Line = APosition.Line then
  begin
    // Mehrere Defined(…): das unter dem Cursor (1-basiert im Token).
    Column := APosition.Character - Token.StartPos.Character + 1;
    for Index := 0 to High(Names) do
    begin
      if (Column >= Starts[Index]) and (Column <= Starts[Index] + Length(Names[Index])) then
      begin
        AName := Names[Index];
      end;
    end;
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
  begin
    Exit(Format('in Zeile %d', [ASite.Range.StartPos.Line + 1]));
  end;
  FileName := AProcessed.Files[ASite.FileIndex];
  Result := Format('in [%s](%s), Zeile %d', [ExtractFileName(FileName), TDocumentUris.FromPath(FileName),
    ASite.Range.StartPos.Line + 1]);
end;

/// <summary>"Win64 · Debug"; ohne Plattform oder Konfiguration nur der bekannte Teil, '' ohne beides.</summary>
function TargetText(const AContext: TConditionalContext): string;
begin
  Result := AContext.Platform;
  if (Result <> '') and (AContext.Config <> '') then
  begin
    Result := Result + ' · ' + AContext.Config;
  end
  else if AContext.Config <> '' then
  begin
    Result := AContext.Config;
  end;
end;

function InInactiveRange(const AProcessed: TPreprocessorResult; const APosition: TTextPosition): Boolean;
var
  Inactive: TInactiveRange;
begin
  for Inactive in AProcessed.InactiveRanges do
  begin
    if (Inactive.FileIndex = 0) and not Before(APosition, Inactive.Range.StartPos) and
      Before(APosition, Inactive.Range.EndPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letztes wirksames $DEFINE/$UNDEF von AName vor der Direktive bei AStart, Include-Dateien an der
/// Stelle ihrer $I-Direktive; False ohne.</summary>
function LastDefineSite(const AProcessed: TPreprocessorResult; const AName: string; const AStart: TTextPosition;
  out ALast: TDefineSite): Boolean;
var
  mSite: TDefineSite;
begin
  ALast := Default(TDefineSite);
  Result := False;
  for mSite in AProcessed.DefineSites do
  begin
    if SameText(mSite.Name, AName) and Before(mSite.RootPos, AStart) then
    begin
      ALast := mSite;
      Result := True;
    end;
  end;
end;

function SiteOrigin(const AProcessed: TPreprocessorResult; const ALast: TDefineSite; const AName: string): string;
begin
  if ALast.Undefine then
  begin
    Result := Format('aufgehoben mit {$UNDEF %s} %s', [AName, SiteText(AProcessed, ALast)]);
  end
  else
  begin
    Result := Format('definiert mit {$DEFINE %s} %s', [AName, SiteText(AProcessed, ALast)]);
  end;
end;

/// <summary>Herkunft ohne $DEFINE davor: Projekt bzw. Compiler, sonst der Grund, warum es fehlt.</summary>
function ContextOrigin(const AContext: TConditionalContext; const AName: string; ADefined: Boolean): string;
var
  mSource: TSymbolSource;
begin
  for mSource in AContext.Sources do
  begin
    if SameText(mSource.Name, AName) then
    begin
      if StartsText('Compiler', mSource.Origin) then
      begin
        Exit(mSource.Origin);
      end;
      Exit('definiert in ' + mSource.Origin);
    end;
  end;
  Result := '';
  if not AContext.HasDefines then
  begin
    Result := 'kein Projekt geladen, nur die Datei ausgewertet';
  end
  else if not ADefined then
  begin
    Result := 'weder im Projekt noch vom Compiler noch mit {$DEFINE} davor gesetzt';
  end;
end;

/// <summary>Hinweis für $DEFINE bzw. $UNDEF selbst; '' sonst.</summary>
function DirectiveNote(const ADirective, AName: string): string;
begin
  Result := '';
  if ADirective = 'DEFINE' then
  begin
    Result := #10#10 + Format('Diese Direktive definiert **%s** ab hier.', [AName]);
  end
  else if ADirective = 'UNDEF' then
  begin
    Result := #10#10 + Format('Diese Direktive hebt **%s** ab hier auf.', [AName]);
  end;
end;

class function TConditionalSymbols.Hover(const AText: string; const APosition: TTextPosition;
  const AContext: TConditionalContext; out AMarkdown: string): Boolean;
var
  mName, mDirective, mState, mOrigin: string;
  mStart: TTextPosition;
  mProcessed: TPreprocessorResult;
  mLast: TDefineSite;
  mHasSite, mDefined: Boolean;
begin
  AMarkdown := '';
  if not AContext.HoverEnabled or not SymbolAt(AText, APosition, mName, mDirective, mStart) then
  begin
    Exit(False);
  end;
  mProcessed := TPascalPreprocessor.Process(AText, OptionsFor(AContext));
  mHasSite := LastDefineSite(mProcessed, mName, mStart, mLast);
  if mHasSite then
  begin
    mDefined := not mLast.Undefine;
    mOrigin := SiteOrigin(mProcessed, mLast, mName);
  end
  else
  begin
    mDefined := IndexText(mName, AContext.Defines) >= 0;
    mOrigin := ContextOrigin(AContext, mName, mDefined);
  end;
  mState := 'nicht definiert';
  if mDefined then
  begin
    mState := 'aktiv';
  end;
  AMarkdown := Format('**%s**: %s', [mName, mState]);
  if mOrigin <> '' then
  begin
    AMarkdown := AMarkdown + ', ' + mOrigin;
  end;
  AMarkdown := AMarkdown + DirectiveNote(mDirective, mName);
  if InInactiveRange(mProcessed, mStart) then
  begin
    AMarkdown := AMarkdown + #10#10 + 'Die Direktive liegt in einem inaktiven Zweig und wirkt nicht.';
  end;
  // Aus einer Include-Datei (#860): unter welchem Projektstand die Datei gelesen wurde.
  if mHasSite and (mLast.FileIndex <> 0) and AContext.HasDefines and (TargetText(AContext) <> '') then
  begin
    AMarkdown := AMarkdown + #10#10 + 'Projekt: ' + TargetText(AContext);
  end;
  Result := True;
end;

function DirectiveName(const AToken: string): string;
var
  Body: string;
  Offset, Index: Integer;
begin
  Body := DirectiveBody(AToken, Offset);
  Index := 1;
  while (Index <= Length(Body)) and IsNameChar(Body[Index]) do
  begin
    Inc(Index);
  end;
  Result := UpperCase(Copy(Body, 1, Index - 1));
end;

function ValueText(AValue: TConditionValue): string;
begin
  case AValue of
    TConditionValue.Yes:
      Result := 'wahr';
    TConditionValue.No:
      Result := 'falsch';
  else
    Result := 'unbekannt = aktiv';
  end;
end;

/// <summary>"aus DCC_RangeChecking (Debug)" bzw. "seit {$R-} in Zeile 4".</summary>
function SwitchOrigin(const AOrigin: string; const AContext: TConditionalContext): string;
begin
  if AOrigin = '' then
  begin
    if AContext.HasDefines then
    begin
      Exit('weder in der .dproj noch mit einem Schalter davor gesetzt');
    end;
    Exit('kein Projekt geladen, nur die Datei ausgewertet');
  end;
  if StartsStr('{$', AOrigin) then
  begin
    Exit('seit ' + AOrigin);
  end;
  Result := 'aus ' + AOrigin;
  if (AContext.Config <> '') and not ContainsStr(AOrigin, '(') then
  begin
    Result := Result + ' (' + AContext.Config + ')';
  end;
end;

/// <summary>Gegenstück beim {$POPOPT} AToken: Für ein gesuchtes {$POPOPT} (ATarget, nicht APush) die Zeile des
/// obersten {$PUSHOPT}, für ein gesuchtes {$PUSHOPT} auf Stufe APending die Zeile von AToken. False sonst.
/// </summary>
function PopPartner(const AToken, ATarget: TPascalToken; APush: Boolean; APending: Integer;
  AStack: TStack<Integer>; out ALine: Integer): Boolean;
begin
  ALine := -1;
  if not APush and (AToken.Offset = ATarget.Offset) then
  begin
    ALine := AStack.Peek;
  end
  else if APush and (APending = AStack.Count - 1) then
  begin
    ALine := AToken.StartPos.Line;
  end;
  Result := ALine >= 0;
end;

/// <summary>Zeile (0-basiert) des Gegenstücks zu {$PUSHOPT} bzw. {$POPOPT} an AToken; -1 ohne.</summary>
function PartnerLine(const AText: string; const AToken: TPascalToken; APush: Boolean): Integer;
var
  mToken: TPascalToken;
  mStack: TStack<Integer>;
  mName: string;
  mPending: Integer;
begin
  Result := -1;
  mPending := -1;
  mStack := TStack<Integer>.Create;
  try
    for mToken in TPascalLexer.Tokenize(AText) do
    begin
      if mToken.Kind <> TPascalTokenKind.Directive then
      begin
        Continue;
      end;
      mName := DirectiveName(mToken.Text);
      if mName = 'PUSHOPT' then
      begin
        if mToken.Offset = AToken.Offset then
        begin
          mPending := mStack.Count;
        end;
        mStack.Push(mToken.StartPos.Line);
      end
      else if (mName = 'POPOPT') and (mStack.Count > 0) then
      begin
        if PopPartner(mToken, AToken, APush, mPending, mStack, Result) then
        begin
          Exit;
        end;
        mStack.Pop;
      end;
    end;
  finally
    mStack.Free;
  end;
end;

function PushOptHover(const AText: string; const AToken: TPascalToken): string;
var
  mLine: Integer;
begin
  Result := '**{$PUSHOPT}** sichert den Schalterstand';
  mLine := PartnerLine(AText, AToken, True);
  if mLine >= 0 then
  begin
    Result := Result + Format('; {$POPOPT} in Zeile %d stellt ihn wieder her.', [mLine + 1]);
  end
  else
  begin
    Result := Result + '; ohne passendes {$POPOPT} gilt der geänderte Stand bis zum Dateiende.';
  end;
end;

function PopOptHover(const AText: string; const AToken: TPascalToken): string;
var
  mLine: Integer;
begin
  mLine := PartnerLine(AText, AToken, False);
  if mLine >= 0 then
  begin
    Result := Format('**{$POPOPT}** stellt den Schalterstand von {$PUSHOPT} in Zeile %d wieder her.',
      [mLine + 1]);
  end
  else
  begin
    Result := '**{$POPOPT}** ohne passendes {$PUSHOPT} davor.';
  end;
end;

/// <summary>Auswertung der Bedingung an AToken aus AProcessed; False, wenn sie fehlt.</summary>
function FindCheck(const AProcessed: TPreprocessorResult; const AToken: TPascalToken;
  out ACheck: TConditionCheck): Boolean;
var
  mItem: TConditionCheck;
begin
  ACheck := Default(TConditionCheck);
  for mItem in AProcessed.Checks do
  begin
    if (mItem.FileIndex = 0) and (mItem.Range.StartPos.Line = AToken.StartPos.Line) and
      (mItem.Range.StartPos.Character = AToken.StartPos.Character) then
    begin
      ACheck := mItem;
      Exit(True);
    end;
  end;
  Result := False;
end;

function UncheckedHover(const AProcessed: TPreprocessorResult; const AToken: TPascalToken): string;
begin
  if InInactiveRange(AProcessed, AToken.StartPos) then
  begin
    Result := 'Die Bedingung liegt in einem inaktiven Zweig und wird nicht ausgewertet.';
  end
  else
  begin
    Result := 'Die Bedingung lässt sich nicht auswerten.';
  end;
end;

function IfOptHover(const ACheck: TConditionCheck; const AContext: TConditionalContext): string;
var
  mPart: TConditionPart;
begin
  mPart := Default(TConditionPart);
  if ACheck.Parts <> nil then
  begin
    mPart := ACheck.Parts[0];
  end;
  case ACheck.Value of
    TConditionValue.Yes:
      Result := Format('**aktiv**: %s %s', [mPart.Value, SwitchOrigin(mPart.Origin, AContext)]);
    TConditionValue.No:
      Result := Format('**inaktiv**: %s %s', [mPart.Value, SwitchOrigin(mPart.Origin, AContext)]);
  else
    Result := Format('**unbekannt = aktiv**: %s %s', [mPart.Text, SwitchOrigin(mPart.Origin, AContext)]);
  end;
end;

function ExpressionHover(const ACheck: TConditionCheck): string;
var
  mPart: TConditionPart;
begin
  Result := Format('**%s**: `%s`', [ValueText(ACheck.Value), ACheck.Expression]);
  if ACheck.Parts <> nil then
  begin
    Result := Result + #10;
  end;
  for mPart in ACheck.Parts do
  begin
    Result := Result + #10 + Format('- `%s` %s', [mPart.Text, mPart.Value]);
    if mPart.Origin <> '' then
    begin
      Result := Result + ' · ' + mPart.Origin;
    end;
  end;
  if ACheck.Value = TConditionValue.Unknown then
  begin
    Result := Result + #10#10 +
      'Ein Wert ist hier nicht bekannt; der Zweig und ein {$ELSE} dazu gelten als aktiv.';
  end;
end;

/// <summary>Hover für {$IF}, {$ELSEIF} und {$IFOPT} (ADirective) an AToken.</summary>
function CheckHover(const AText: string; const AToken: TPascalToken; const ADirective: string;
  const AContext: TConditionalContext): string;
var
  mProcessed: TPreprocessorResult;
  mCheck: TConditionCheck;
begin
  mProcessed := TPascalPreprocessor.Process(AText, OptionsFor(AContext));
  if not FindCheck(mProcessed, AToken, mCheck) then
  begin
    Result := UncheckedHover(mProcessed, AToken);
  end
  else if ADirective = 'IFOPT' then
  begin
    Result := IfOptHover(mCheck, AContext);
  end
  else
  begin
    Result := ExpressionHover(mCheck);
  end;
end;

class function TConditionalSymbols.ConditionHover(const AText: string; const APosition: TTextPosition;
  const AContext: TConditionalContext; out AMarkdown: string): Boolean;
var
  mToken: TPascalToken;
  mName: string;
begin
  AMarkdown := '';
  Result := AContext.HoverEnabled and DirectiveAt(AText, APosition, mToken);
  if not Result then
  begin
    Exit;
  end;
  mName := DirectiveName(mToken.Text);
  if mName = 'PUSHOPT' then
  begin
    AMarkdown := PushOptHover(AText, mToken);
  end
  else if mName = 'POPOPT' then
  begin
    AMarkdown := PopOptHover(AText, mToken);
  end
  else if MatchStr(mName, ['IF', 'ELSEIF', 'IFOPT']) then
  begin
    AMarkdown := CheckHover(AText, mToken, mName, AContext);
  end
  else
  begin
    Result := False;
  end;
end;

class function TConditionalSymbols.IsSymbolContext(const ALineBefore: string; out APrefix: string): Boolean;
var
  Open, Index, Offset: Integer;
  Body, Directive, Rest: string;
begin
  APrefix := '';
  Open := 0;
  while PosEx('{$', ALineBefore, Open + 1) > 0 do
  begin
    Open := PosEx('{$', ALineBefore, Open + 1);
  end;
  if (Open = 0) or (PosEx('}', ALineBefore, Open) > 0) then
  begin
    Exit(False);
  end;
  Body := DirectiveBody(Copy(ALineBefore, Open, MaxInt), Offset);
  // Getippten Teil des Namens abtrennen.
  Index := Length(Body);
  while (Index > 0) and IsNameChar(Body[Index]) do
  begin
    Dec(Index);
  end;
  APrefix := Copy(Body, Index + 1, MaxInt);
  Rest := Copy(Body, 1, Index);
  Index := 1;
  while (Index <= Length(Rest)) and IsNameChar(Rest[Index]) do
  begin
    Inc(Index);
  end;
  Directive := UpperCase(Copy(Rest, 1, Index - 1));
  if MatchStr(Directive, ['IFDEF', 'IFNDEF', 'DEFINE', 'UNDEF']) then
  begin
    Exit(Trim(Copy(Rest, Index, MaxInt)) = '');
  end;
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
    begin
      Exit;
    end;
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
    begin
      Add(Source.Name, Source.Origin, True);
    end;
    Processed := TPascalPreprocessor.Process(AText, OptionsFor(AContext));
    for Site in Processed.DefineSites do
    begin
      if not Site.Undefine then
      begin
        Add(Site.Name, '{$DEFINE} ' + StringReplace(SiteText(Processed, Site), 'in ', '', []),
          IndexText(Site.Name, Processed.Defines) >= 0);
      end;
    end;
    for Token in TPascalLexer.Tokenize(AText) do
    begin
      if Token.Kind = TPascalTokenKind.Directive then
      begin
        SplitSymbols(Token.Text, Directive, Names, Starts);
        for Name in Names do
        begin
          Add(Name, Format('in der Datei verwendet (Zeile %d)', [Token.StartPos.Line + 1]),
            IndexText(Name, Processed.Defines) >= 0);
        end;
      end;
    end;
    for Platform in OtherPlatforms do
    begin
      for Name in TTextDefines.Predefined(Platform, 0) do
      begin
        Add(Name, 'Compiler-Vorgabe auf ' + Platform, False);
      end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Seen.Free;
  end;
end;

end.
