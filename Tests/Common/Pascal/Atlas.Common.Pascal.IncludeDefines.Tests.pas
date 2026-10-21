unit Atlas.Common.Pascal.IncludeDefines.Tests;

// Tests für Defines aus Include-Dateien und Projekt in Syntaxprüfung,
// Editor-Baum und Regelprüfung (#860). Die Include-Dateien liefert ein
// Resolver im Speicher; Hover und check_code stehen bei ihren Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIncludeDefinesTests = class
  public
    [TearDown]
    procedure TearDown;
    /// <summary>{$I datei} und {$INCLUDE datei} zählen, Schalter wie {$I+} und {$IFDEF} nicht.</summary>
    [Test]
    procedure HasIncludesFindsIncludeDirectives;
    /// <summary>Abnahme: {$DEFINE FOO} aus defs.inc wählt den Zweig; keine Syntaxdiagnose.</summary>
    [Test]
    procedure ActiveDiagnosticsReadIncludeDefines;
    /// <summary>Der gemeinsame Baum liest {$I} über den IncludeProvider, behält den Präprozessor-Lauf und liest
    /// nach IncludesChanged neu.</summary>
    [Test]
    procedure SharedTreeReadsIncludesAndRefreshes;
    /// <summary>Abblenden und Include-Befunde aus dem Lauf des gemeinsamen Baums.</summary>
    [Test]
    procedure InactiveRegionsFromSharedRun;
    /// <summary>Abnahme: Die Regelprüfung meldet für Win64 keinen Fehler im Zweig, der dort inaktiv ist, und
    /// liest Defines aus Include-Dateien.</summary>
    [Test]
    procedure CheckerUsesProjectAndIncludeDefines;
    /// <summary>Inlay-Hinweis „definiert FOO“ hinter {$I}: nur geprüfte Symbole, $UNDEF nimmt heraus,
    /// abschaltbar.</summary>
    [Test]
    procedure InlayHintNamesUsedIncludeSymbols;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Lsp.InlayHints;

const
  MainFile = 'C:\P\U.pas';
  // Ohne FOO ist der {$IFNDEF FOO}-Zweig aktiv; dort steht ein zweites uses.
  Accepted =
    'unit U;'#10 +                                          // 0
    'interface'#10 +                                        // 1
    '{$I defs.inc}'#10 +                                    // 2
    '{$IFDEF FOO} uses A; {$ENDIF}'#10 +                    // 3
    '{$IFNDEF FOO} uses B; uses C; {$ENDIF}'#10 +           // 4
    'implementation'#10 +                                   // 5
    'end.';

var
  // Inhalt von defs.inc in den Tests.
  DefsText: string;

function Resolver: TIncludeResolver;
begin
  Result :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      Result := SameText(AName, 'defs.inc');
      AFileName := 'C:\P\defs.inc';
      AText := DefsText;
    end;
end;

function DiagnosticCount(const AText: string; const AOptions: TPreprocessorOptions): Integer;
var
  Diagnostics: TArray<TSyntaxDiagnostic>;
begin
  if not TPascalParser.ActiveDiagnostics(AText, AOptions, Diagnostics) then
    Exit(-1);
  Result := Length(Diagnostics);
end;

procedure TIncludeDefinesTests.TearDown;
begin
  TSyntaxTreeCache.SetIncludeProvider(nil);
  DefsText := '';
end;

procedure TIncludeDefinesTests.HasIncludesFindsIncludeDirectives;
begin
  Assert.IsTrue(TPascalPreprocessor.HasIncludes('{$I defs.inc}'));
  Assert.IsTrue(TPascalPreprocessor.HasIncludes('{$i ''mit leer.inc''}'));
  Assert.IsTrue(TPascalPreprocessor.HasIncludes('(*$INCLUDE defs.inc*)'));
  Assert.IsFalse(TPascalPreprocessor.HasIncludes('{$I+}{$IFDEF X}{$ENDIF}'));
  Assert.IsFalse(TPascalPreprocessor.HasIncludes('S := ''$I x'';'));
end;

procedure TIncludeDefinesTests.ActiveDiagnosticsReadIncludeDefines;
begin
  DefsText := '{$DEFINE FOO}';
  // Ohne Resolver gilt FOO nicht: das zweite uses ist ein Fehler.
  Assert.IsTrue(DiagnosticCount(Accepted, TPascalPreprocessor.EditorOptions(nil)) > 0, 'ohne Resolver');
  Assert.AreEqual(0, DiagnosticCount(Accepted, TPascalPreprocessor.EditorOptions(nil, MainFile, Resolver)),
    'mit defs.inc');
  // Der Fall aus dem Issue: beide Zweige gültig, keine Diagnose.
  Assert.AreEqual(0, DiagnosticCount('unit U;'#10'interface'#10'{$I defs.inc}'#10 +
    '{$IFDEF FOO} uses A; {$ENDIF} {$IFNDEF FOO} uses B; {$ENDIF}'#10'implementation'#10'end.',
    TPascalPreprocessor.EditorOptions(nil, MainFile, Resolver)));
end;

procedure TIncludeDefinesTests.SharedTreeReadsIncludesAndRefreshes;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
begin
  DefsText := '{$DEFINE FOO}';
  Document := TTextDocument.Create('file:///c:/p/u.pas', 'objectpascal', 1, Accepted);
  Shared := TSyntaxTreeCache.Get(Document);
  Assert.IsTrue(Length(Shared.Tree.Diagnostics) > 0, 'ohne IncludeProvider');
  Assert.IsFalse(Shared.IncludesResolved);
  TSyntaxTreeCache.SetIncludeProvider(
    function(const AUri: string): TIncludeResolver
    begin
      Result := Resolver;
    end);
  Shared := TSyntaxTreeCache.Get(Document);
  Assert.AreEqual(0, Integer(Length(Shared.Tree.Diagnostics)), 'mit defs.inc');
  Assert.IsTrue(Shared.IncludesResolved);
  Assert.AreEqual(1, Integer(Length(Shared.Processed.DefineSites)));
  Assert.AreEqual('FOO', Shared.Processed.DefineSites[0].Name);
  // Dieselbe Momentaufnahme: kein neuer Lauf, bis sich eine Include-Datei ändert.
  DefsText := '';
  Assert.AreEqual(0, Integer(Length(TSyntaxTreeCache.Get(Document).Tree.Diagnostics)), 'noch der alte Stand');
  TSyntaxTreeCache.IncludesChanged;
  Assert.IsTrue(Length(TSyntaxTreeCache.Get(Document).Tree.Diagnostics) > 0, 'neu gelesen');
end;

procedure TIncludeDefinesTests.InactiveRegionsFromSharedRun;
var
  Tree: TSyntaxTree;
  Processed: TPreprocessorResult;
  Regions: TArray<TLspInactiveRegion>;
  Issues: TArray<TPreprocessorIssue>;
begin
  DefsText := '{$DEFINE FOO}';
  Tree := TPascalParser.ParseActive(Accepted + #10'{$I fehlt.inc}', TPascalPreprocessor.EditorOptions(nil,
    MainFile, Resolver), nil, Processed);
  try
    Regions := TLspInactiveRegions.Regions(Processed, True, Issues);
    Assert.AreEqual(1, Integer(Length(Regions)));
    Assert.AreEqual(4, Regions[0].Range.StartPos.Line);
    Assert.AreEqual('not FOO', Regions[0].Condition);
    Assert.AreEqual(1, Integer(Length(Issues)), 'fehlt.inc');
    Assert.AreEqual(7, Issues[0].Range.StartPos.Line);
    // Ohne Resolver im Lauf keine Include-Befunde.
    Regions := TLspInactiveRegions.Regions(Processed, False, Issues);
    Assert.AreEqual(0, Integer(Length(Issues)));
  finally
    Tree.Free;
  end;
end;

procedure TIncludeDefinesTests.CheckerUsesProjectAndIncludeDefines;
const
  Win64Unit =
    'unit Ziel;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10 +
    '{$IFDEF WIN64}'#10'  X;'#10'{$ELSE}'#10'  if then'#10'{$ENDIF}'#10'end;'#10'end.';

  function SyntaxFindings(const AText: string; const ASource: TCheckSource): Integer;
  var
    Finding: TRuleFinding;
  begin
    Result := 0;
    for Finding in TFileChecker.CheckText(nil, TServerSettings.Default, 'Ziel.pas', AText, ASource) do
      if Finding.RuleId = SyntaxRuleId then
        Inc(Result);
  end;

begin
  // Vorgabe Win32: der {$ELSE}-Zweig ist aktiv und kaputt.
  Assert.IsTrue(Length(TFileChecker.CheckText(nil, TServerSettings.Default, 'Ziel.pas', Win64Unit)) > 0, 'Win32');
  Assert.AreEqual(0, SyntaxFindings(Win64Unit, TCheckSource.Create(MainFile,
    TPascalPreprocessor.PredefinedSymbols('Win64', 37), nil)), 'Win64');
  DefsText := '{$DEFINE FOO}';
  Assert.IsTrue(SyntaxFindings(Accepted, TCheckSource.Default) > 0, 'ohne Include-Dateien');
  Assert.AreEqual(0, SyntaxFindings(Accepted, TCheckSource.Create(MainFile, nil, Resolver)), 'mit defs.inc');
end;

procedure TIncludeDefinesTests.InlayHintNamesUsedIncludeSymbols;
const
  Source =
    'unit U;'#10 +                                          // 0
    'interface'#10 +                                        // 1
    '{$I defs.inc}'#10 +                                    // 2
    '{$IFDEF FOO}{$ENDIF}'#10 +                             // 3
    '{$IF Defined(BAR) and not Defined(GONE)}{$IFEND}'#10 + // 4
    'implementation'#10 +                                   // 5
    'end.';
var
  Tree: TSyntaxTree;
  Processed: TPreprocessorResult;
  Settings: TInlayHintSettings;
  Hints: TArray<TInlayHint>;
  Json: TJSONArray;
begin
  // UNUSED prüft die Unit nicht, GONE hebt die Include-Datei wieder auf.
  DefsText := '{$DEFINE FOO}'#10'{$DEFINE UNUSED}'#10'{$DEFINE GONE}'#10'{$DEFINE BAR}'#10'{$UNDEF GONE}';
  Tree := TPascalParser.ParseActive(Source, TPascalPreprocessor.EditorOptions(nil, MainFile, Resolver), nil,
    Processed);
  try
    Settings := TInlayHintSettings.Default;
    Settings.ParameterNames := False;
    Settings.InferredTypes := False;
    Settings.EndMarkers := False;
    Hints := TLspInlayHints.Collect(nil, nil, Tree, Source, MainFile, TTextRange.Create(0, 0, 7, 0), Settings,
      nil, Processed);
    Assert.AreEqual(1, Integer(Length(Hints)));
    Assert.AreEqual('definiert FOO, BAR', Hints[0].Text);
    Assert.AreEqual(2, Hints[0].Position.Line);
    Assert.AreEqual(13, Hints[0].Position.Character, 'hinter der Direktive');
    Json := TLspInlayHints.ToJson(Hints);
    try
      Assert.AreEqual('defs.inc', Json.Items[0].GetValue<string>('data.includeDefines.file'));
      Assert.AreEqual(2, Json.Items[0].GetValue<TJSONArray>('data.includeDefines.names').Count);
      Assert.IsNull((Json.Items[0] as TJSONObject).GetValue('kind'), 'ohne kind wie Endmarken');
    finally
      Json.Free;
    end;
    // Außerhalb des Bereichs und abgeschaltet: nichts.
    Assert.AreEqual(0, Integer(Length(TLspInlayHints.IncludeDefines(Tree, Processed,
      TTextRange.Create(3, 0, 7, 0)))));
    Settings.IncludeDefines := False;
    Assert.AreEqual(0, Integer(Length(TLspInlayHints.Collect(nil, nil, Tree, Source, MainFile,
      TTextRange.Create(0, 0, 7, 0), Settings, nil, Processed))));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIncludeDefinesTests);

end.
