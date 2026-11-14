unit Atlas.Common.Lsp.ConditionalSymbols.Tests;

// Tests für Zustand und Herkunft bedingter Symbole in Direktiven (#102, Teil 2).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionalSymbolsTests = class
  public
    /// <summary>Abnahme: {$IFDEF DEBUG} nennt „aktiv, definiert in Konfiguration Debug (.dproj)“.</summary>
    [Test]
    procedure HoverNamesConfiguration;
    /// <summary>Abnahme: {$DEFINE FOO} in einer Include-Datei mit Datei und Zeile.</summary>
    [Test]
    procedure HoverNamesIncludeFileAndLine;
    [Test]
    procedure HoverFollowsDefineAndUndefInFile;
    [Test]
    procedure HoverNamesCompilerAndIdeSymbols;
    [Test]
    procedure HoverPicksDefinedUnderCursor;
    [Test]
    procedure HoverNotesInactiveBranchAndUnknownSymbol;
    [Test]
    procedure HoverIsSwitchable;
    [Test]
    procedure DetectsSymbolContexts;
    [Test]
    procedure CandidatesWithOrigin;
    /// <summary>#847: Hover auf {$IF} nennt Wert und Teilwerte mit Herkunft.</summary>
    [Test]
    procedure ConditionHoverExplainsParts;
    /// <summary>#847: Hover auf {$IFOPT} nennt Schalter aus der .dproj bzw. dem lokalen Schalter davor.</summary>
    [Test]
    procedure ConditionHoverNamesSwitchOrigin;
    /// <summary>#847: {$PUSHOPT} und {$POPOPT} nennen ihr Gegenstück.</summary>
    [Test]
    procedure ConditionHoverPairsPushAndPop;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.ConditionalSymbols;

function Context: TConditionalContext;
begin
  Result := TConditionalContext.Default;
  Result.HasDefines := True;
  Result.Defines := ['DEBUG', 'IDEONLY', 'MSWINDOWS', 'WIN64'];
  Result.Sources := TConditionalSymbols.SourcesOf(['DEBUG', 'IDEONLY'],
    [TPair<string, string>.Create('DEBUG', 'Konfiguration Debug')], ['MSWINDOWS', 'WIN64'], 'Win64');
  Result.FileName := 'C:\P\Haupt.pas';
  Result.ResolveInclude :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      Result := SameText(AName, 'Defs.inc');
      AFileName := 'C:\P\Defs.inc';
      AText := '// Gemeinsame Symbole'#10'{$DEFINE FOO}';
    end;
end;

function HoverAt(const AText: string; ALine, ACharacter: Integer; const AContext: TConditionalContext): string;
begin
  if not TConditionalSymbols.Hover(AText, TTextPosition.Create(ALine, ACharacter), AContext, Result) then
  begin
    Result := '-';
  end;
end;

procedure TConditionalSymbolsTests.HoverNamesConfiguration;
begin
  Assert.AreEqual('**DEBUG**: aktiv, definiert in Konfiguration Debug (.dproj)',
    HoverAt('unit U;'#10'{$IFDEF DEBUG}'#10'{$ENDIF}', 1, 10, Context));
  // Auch über dem Direktivennamen und bei {$IFNDEF}.
  Assert.AreEqual('**DEBUG**: aktiv, definiert in Konfiguration Debug (.dproj)',
    HoverAt('unit U;'#10'{$IFNDEF DEBUG}'#10'{$ENDIF}', 1, 3, Context));
end;

procedure TConditionalSymbolsTests.HoverNamesIncludeFileAndLine;
var
  mMarkdown: string;
  mTarget: TConditionalContext;
begin
  mMarkdown := HoverAt('unit U;'#10'{$I Defs.inc}'#10'{$IFDEF FOO}'#10'{$ENDIF}', 2, 9, Context);
  Assert.IsTrue(StartsStr('**FOO**: aktiv, definiert mit {$DEFINE FOO} in [Defs.inc](', mMarkdown), mMarkdown);
  Assert.IsTrue(EndsStr('), Zeile 2', mMarkdown), mMarkdown);
  // Mit Zielplattform und Konfiguration nennt der Hover den Projektstand (#860).
  mTarget := Context;
  mTarget.Platform := 'Win64';
  mTarget.Config := 'Debug';
  mMarkdown := HoverAt('unit U;'#10'{$I Defs.inc}'#10'{$IFDEF FOO}'#10'{$ENDIF}', 2, 9, mTarget);
  Assert.IsTrue(EndsStr('), Zeile 2'#10#10'Projekt: Win64 · Debug', mMarkdown), mMarkdown);
  // Vor der $I-Direktive gilt FOO noch nicht.
  Assert.IsTrue(StartsStr('**FOO**: nicht definiert',
    HoverAt('unit U;'#10'{$IFDEF FOO}'#10'{$ENDIF}'#10'{$I Defs.inc}', 1, 9, Context)));
end;

procedure TConditionalSymbolsTests.HoverFollowsDefineAndUndefInFile;
const
  cSource =
    'unit U;'#10 +                // 0
    '{$DEFINE BAR}'#10 +          // 1
    '{$IFDEF BAR}{$ENDIF}'#10 +   // 2
    '{$UNDEF DEBUG}'#10 +         // 3
    '{$IFDEF DEBUG}{$ENDIF}'#10 + // 4
    'end.';
var
  mMarkdown: string;
begin
  Assert.AreEqual('**BAR**: aktiv, definiert mit {$DEFINE BAR} in Zeile 2', HoverAt(cSource, 2, 9, Context));
  Assert.AreEqual('**DEBUG**: nicht definiert, aufgehoben mit {$UNDEF DEBUG} in Zeile 4',
    HoverAt(cSource, 4, 9, Context));
  // Über der Direktive selbst: Zustand davor und was sie tut.
  mMarkdown := HoverAt(cSource, 1, 10, Context);
  Assert.IsTrue(StartsStr('**BAR**: nicht definiert', mMarkdown), mMarkdown);
  Assert.IsTrue(ContainsStr(mMarkdown, 'Diese Direktive definiert **BAR** ab hier.'), mMarkdown);
  Assert.IsTrue(ContainsStr(HoverAt(cSource, 3, 9, Context), 'Diese Direktive hebt **DEBUG** ab hier auf.'));
end;

procedure TConditionalSymbolsTests.HoverNamesCompilerAndIdeSymbols;
begin
  Assert.AreEqual('**MSWINDOWS**: aktiv, Compiler-Vorgabe (Plattform Win64)',
    HoverAt('{$IFDEF MSWINDOWS}{$ENDIF}', 0, 10, Context));
  Assert.AreEqual('**IDEONLY**: aktiv, definiert in Projektoptionen der IDE',
    HoverAt('{$IFDEF IDEONLY}{$ENDIF}', 0, 10, Context));
end;

procedure TConditionalSymbolsTests.HoverPicksDefinedUnderCursor;
const
  cSource = '{$IF Defined(DEBUG) and not Defined(LINUX)}{$IFEND}';
begin
  Assert.IsTrue(StartsStr('**DEBUG**: aktiv', HoverAt(cSource, 0, 15, Context)));
  Assert.IsTrue(StartsStr('**LINUX**: nicht definiert', HoverAt(cSource, 0, 38, Context)));
  // Zwischen den Namen und bei mehreren Defined: nichts.
  Assert.AreEqual('-', HoverAt(cSource, 0, 24, Context));
  // Ein einziges Defined gilt überall in der Direktive.
  Assert.IsTrue(StartsStr('**DEBUG**', HoverAt('{$ELSEIF Defined(DEBUG)}', 0, 3, Context)));
end;

procedure TConditionalSymbolsTests.HoverNotesInactiveBranchAndUnknownSymbol;
var
  mMarkdown: string;
  mLoose: TConditionalContext;
begin
  mMarkdown := HoverAt('{$IFDEF LINUX}'#10'{$IFDEF DEBUG}{$ENDIF}'#10'{$ENDIF}', 1, 9, Context);
  Assert.IsTrue(ContainsStr(mMarkdown, 'inaktiven Zweig'), mMarkdown);
  Assert.AreEqual('**XYZ**: nicht definiert, weder im Projekt noch vom Compiler noch mit {$DEFINE} davor gesetzt',
    HoverAt('{$IFDEF XYZ}{$ENDIF}', 0, 9, Context));
  // Ohne Projekt nur die Datei.
  mLoose := TConditionalContext.Default;
  Assert.AreEqual('**XYZ**: nicht definiert, kein Projekt geladen, nur die Datei ausgewertet',
    HoverAt('{$IFDEF XYZ}{$ENDIF}', 0, 9, mLoose));
  // Andere Direktiven haben kein Symbol.
  Assert.AreEqual('-', HoverAt('{$R+}', 0, 2, Context));
  Assert.AreEqual('-', HoverAt('unit U;', 0, 2, Context));
end;

function ConditionAt(const AText: string; ALine, ACharacter: Integer; const AContext: TConditionalContext): string;
begin
  if not TConditionalSymbols.ConditionHover(AText, TTextPosition.Create(ALine, ACharacter), AContext, Result) then
  begin
    Result := '-';
  end;
end;

function SwitchContext: TConditionalContext;
begin
  Result := Context;
  Result.Defines := Result.Defines + ['CPU64BITS', '$R+'];
  Result.Config := 'Debug';
end;

procedure TConditionalSymbolsTests.ConditionHoverExplainsParts;
var
  mMarkdown: string;
  mOff: TConditionalContext;
begin
  mMarkdown := ConditionAt('{$IF SizeOf(Pointer) = 8}'#10'{$IFEND}', 0, 3, SwitchContext);
  Assert.IsTrue(StartsStr('**wahr**: `SizeOf(Pointer) = 8`', mMarkdown), mMarkdown);
  Assert.IsTrue(ContainsStr(mMarkdown, '- `SizeOf(Pointer)` 8 · Zielplattform Win64'), mMarkdown);
  mMarkdown := ConditionAt('{$IF Declared(Unbekannt)}'#10'{$IFEND}', 0, 3, SwitchContext);
  Assert.IsTrue(StartsStr('**unbekannt = aktiv**', mMarkdown), mMarkdown);
  Assert.IsTrue(ContainsStr(mMarkdown, '{$ELSE} dazu gelten als aktiv'), mMarkdown);
  // Im inaktiven Zweig wird nichts ausgewertet.
  mMarkdown := ConditionAt('{$IFDEF LINUX}'#10'{$IF SizeOf(Pointer) = 8}{$IFEND}'#10'{$ENDIF}', 1, 3, SwitchContext);
  Assert.IsTrue(ContainsStr(mMarkdown, 'inaktiven Zweig'), mMarkdown);
  // Auf anderen Direktiven und abgeschaltet: nichts.
  Assert.AreEqual('-', ConditionAt('{$IFDEF DEBUG}{$ENDIF}', 0, 3, SwitchContext));
  mOff := SwitchContext;
  mOff.HoverEnabled := False;
  Assert.AreEqual('-', ConditionAt('{$IF SizeOf(Pointer) = 8}{$IFEND}', 0, 3, mOff));
  // Schaltereinträge sind keine Symbole.
  Assert.AreEqual<NativeInt>(0, Length(TConditionalSymbols.SourcesOf(['$R+'], nil, nil, '')));
end;

procedure TConditionalSymbolsTests.ConditionHoverNamesSwitchOrigin;
const
  cSource =
    '{$IFOPT R+}'#10 + // 0
    '{$ENDIF}'#10 +    // 1
    'x'#10 +           // 2
    '{$R-}'#10 +       // 3
    '{$IFOPT R+}'#10 + // 4
    '{$ENDIF}';
begin
  Assert.AreEqual('**aktiv**: R+ aus DCC_RangeChecking (Debug)', ConditionAt(cSource, 0, 3, SwitchContext));
  Assert.AreEqual('**inaktiv**: R- seit {$R-} in Zeile 4', ConditionAt(cSource, 4, 3, SwitchContext));
  Assert.IsTrue(StartsStr('**unbekannt = aktiv**: R+ kein Projekt',
    ConditionAt(cSource, 0, 3, TConditionalContext.Default)));
end;

procedure TConditionalSymbolsTests.ConditionHoverPairsPushAndPop;
const
  cSource =
    '{$PUSHOPT}'#10 + // 0
    '{$PUSHOPT}'#10 + // 1
    '{$POPOPT}'#10 +  // 2
    '{$POPOPT}'#10 +  // 3
    '{$POPOPT}';      // 4
begin
  Assert.AreEqual('**{$PUSHOPT}** sichert den Schalterstand; {$POPOPT} in Zeile 4 stellt ihn wieder her.',
    ConditionAt(cSource, 0, 3, Context));
  Assert.IsTrue(ContainsStr(ConditionAt(cSource, 1, 3, Context), 'Zeile 3'));
  Assert.AreEqual('**{$POPOPT}** stellt den Schalterstand von {$PUSHOPT} in Zeile 2 wieder her.',
    ConditionAt(cSource, 2, 3, Context));
  Assert.AreEqual('**{$POPOPT}** ohne passendes {$PUSHOPT} davor.', ConditionAt(cSource, 4, 3, Context));
end;

procedure TConditionalSymbolsTests.HoverIsSwitchable;
var
  mOff: TConditionalContext;
begin
  mOff := Context;
  mOff.HoverEnabled := False;
  Assert.AreEqual('-', HoverAt('{$IFDEF DEBUG}{$ENDIF}', 0, 9, mOff));
end;

procedure TConditionalSymbolsTests.DetectsSymbolContexts;
var
  mPrefix: string;
begin
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('  {$IFDEF ', mPrefix));
  Assert.AreEqual('', mPrefix);
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$ifndef DE', mPrefix));
  Assert.AreEqual('DE', mPrefix);
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$DEFINE ', mPrefix));
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$UNDEF X', mPrefix));
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$IF Defined(', mPrefix));
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$IF Defined(A) or Defined( WI', mPrefix));
  Assert.AreEqual('WI', mPrefix);
  Assert.IsTrue(TConditionalSymbols.IsSymbolContext('{$ELSEIF not Defined(', mPrefix));
  Assert.IsFalse(TConditionalSymbols.IsSymbolContext('{$IFDEF DEBUG ', mPrefix), 'schon ein Name');
  Assert.IsFalse(TConditionalSymbols.IsSymbolContext('{$IF CompilerVersion', mPrefix));
  Assert.IsFalse(TConditionalSymbols.IsSymbolContext('{$IFDEF DEBUG} X', mPrefix), 'Direktive zu');
  Assert.IsFalse(TConditionalSymbols.IsSymbolContext('{$IFDE', mPrefix), 'Direktivenname');
  Assert.IsFalse(TConditionalSymbols.IsSymbolContext('  IFDEF ', mPrefix));
end;

procedure TConditionalSymbolsTests.CandidatesWithOrigin;
var
  mFound: TArray<TConditionalSymbol>;
  mText: string;

  function Find(const AName: string): TConditionalSymbol;
  var
    mSymbol: TConditionalSymbol;
  begin
    Result := Default(TConditionalSymbol);
    for mSymbol in mFound do
    begin
      if mSymbol.Name = AName then
      begin
        Exit(mSymbol);
      end;
    end;
  end;

  function IndexOf(const AName: string): Integer;
  begin
    for Result := 0 to High(mFound) do
    begin
      if mFound[Result].Name = AName then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  function CountOf(const AName: string): Integer;
  var
    mSymbol: TConditionalSymbol;
  begin
    Result := 0;
    for mSymbol in mFound do
    begin
      if mSymbol.Name = AName then
      begin
        Inc(Result);
      end;
    end;
  end;

begin
  mText := 'unit U;'#10'{$I Defs.inc}'#10'{$DEFINE LOKAL}'#10'{$IFDEF Benutzt}{$ENDIF}'#10'end.';
  mFound := TConditionalSymbols.Candidates(mText, Context);
  Assert.AreEqual('Konfiguration Debug (.dproj)', Find('DEBUG').Detail);
  Assert.IsTrue(Find('DEBUG').Active);
  Assert.AreEqual('Compiler-Vorgabe (Plattform Win64)', Find('WIN64').Detail);
  Assert.AreEqual('{$DEFINE} [Defs.inc](file:///c%3A/P/Defs.inc), Zeile 2', Find('FOO').Detail);
  Assert.AreEqual('{$DEFINE} Zeile 3', Find('LOKAL').Detail);
  Assert.IsTrue(Find('LOKAL').Active);
  Assert.AreEqual('in der Datei verwendet (Zeile 4)', Find('BENUTZT').Detail);
  Assert.IsFalse(Find('BENUTZT').Active);
  // Compiler-Symbole anderer Plattformen am Ende, abgeschwächt.
  Assert.IsFalse(Find('LINUX').Active);
  Assert.IsTrue(StartsStr('Compiler-Vorgabe auf ', Find('LINUX').Detail));
  Assert.IsTrue(IndexOf('DEBUG') < IndexOf('FOO'));
  Assert.IsTrue(IndexOf('FOO') < IndexOf('BENUTZT'));
  Assert.IsTrue(IndexOf('BENUTZT') < IndexOf('LINUX'));
  // Jedes Symbol nur einmal.
  Assert.AreEqual(1, CountOf('MSWINDOWS'));
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionalSymbolsTests);

end.
