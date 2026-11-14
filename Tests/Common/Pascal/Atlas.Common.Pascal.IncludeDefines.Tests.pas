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
    /// <summary>{$IF…} und (*$IF…*) in jeder Schreibung, andere Direktiven und $IF ohne Klammer nicht.</summary>
    [Test]
    procedure HasConditionalsFindsConditionalDirectives;
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
  System.Generics.Collections,
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
  cMainFile = 'C:\P\U.pas';
  // Ohne FOO ist der {$IFNDEF FOO}-Zweig aktiv; dort steht ein zweites uses.
  cAccepted =
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
  mDiagnostics: TArray<TSyntaxDiagnostic>;
begin
  if not TPascalParser.ActiveDiagnostics(AText, AOptions, mDiagnostics) then
  begin
    Exit(-1);
  end;
  Result := Length(mDiagnostics);
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

procedure TIncludeDefinesTests.HasConditionalsFindsConditionalDirectives;
begin
  Assert.IsTrue(TPascalPreprocessor.HasConditionals('{$IFDEF X}{$ENDIF}'));
  Assert.IsTrue(TPascalPreprocessor.HasConditionals('{$ifndef X}{$endif}'));
  Assert.IsTrue(TPascalPreprocessor.HasConditionals('(*$If Defined(X)*)(*$IfEnd*)'));
  Assert.IsFalse(TPascalPreprocessor.HasConditionals('{$R+}{$I defs.inc}'));
  Assert.IsFalse(TPascalPreprocessor.HasConditionals('S := ''$IF'';*$IF'));
  Assert.IsFalse(TPascalPreprocessor.HasConditionals('{$I'));
end;

procedure TIncludeDefinesTests.ActiveDiagnosticsReadIncludeDefines;
begin
  DefsText := '{$DEFINE FOO}';
  // Ohne Resolver gilt FOO nicht: das zweite uses ist ein Fehler.
  Assert.IsTrue(DiagnosticCount(cAccepted, TPascalPreprocessor.EditorOptions(nil)) > 0, 'ohne Resolver');
  Assert.AreEqual(0, DiagnosticCount(cAccepted, TPascalPreprocessor.EditorOptions(nil, cMainFile, Resolver())),
    'mit defs.inc');
  // Der Fall aus dem Issue: beide Zweige gültig, keine Diagnose.
  Assert.AreEqual(0, DiagnosticCount('unit U;'#10'interface'#10'{$I defs.inc}'#10 +
    '{$IFDEF FOO} uses A; {$ENDIF} {$IFNDEF FOO} uses B; {$ENDIF}'#10'implementation'#10'end.',
    TPascalPreprocessor.EditorOptions(nil, cMainFile, Resolver())));
end;

procedure TIncludeDefinesTests.SharedTreeReadsIncludesAndRefreshes;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
begin
  DefsText := '{$DEFINE FOO}';
  mDocument := TTextDocument.Create('file:///c:/p/u.pas', 'objectpascal', 1, cAccepted);
  mShared := TSyntaxTreeCache.Get(mDocument);
  Assert.IsTrue(Length(mShared.Tree.Diagnostics) > 0, 'ohne IncludeProvider');
  Assert.IsFalse(mShared.IncludesResolved);
  TSyntaxTreeCache.SetIncludeProvider(
    function(const AUri: string): TIncludeResolver
    begin
      Result := Resolver();
    end);
  mShared := TSyntaxTreeCache.Get(mDocument);
  Assert.AreEqual(0, Integer(Length(mShared.Tree.Diagnostics)), 'mit defs.inc');
  Assert.IsTrue(mShared.IncludesResolved);
  Assert.AreEqual(1, Integer(Length(mShared.Processed.DefineSites)));
  Assert.AreEqual('FOO', mShared.Processed.DefineSites[0].Name);
  // Dieselbe Momentaufnahme: kein neuer Lauf, bis sich eine Include-Datei ändert.
  DefsText := '';
  Assert.AreEqual(0, Integer(Length(TSyntaxTreeCache.Get(mDocument).Tree.Diagnostics)), 'noch der alte Stand');
  TSyntaxTreeCache.IncludesChanged;
  Assert.IsTrue(Length(TSyntaxTreeCache.Get(mDocument).Tree.Diagnostics) > 0, 'neu gelesen');
end;

procedure TIncludeDefinesTests.InactiveRegionsFromSharedRun;
var
  mTree: TSyntaxTree;
  mProcessed: TPreprocessorResult;
  mRegions: TArray<TLspInactiveRegion>;
  mIssues: TArray<TPreprocessorIssue>;
begin
  DefsText := '{$DEFINE FOO}';
  mTree := TPascalParser.ParseActive(cAccepted + #10'{$I fehlt.inc}', TPascalPreprocessor.EditorOptions(nil,
    cMainFile, Resolver()), nil, mProcessed);
  try
    mRegions := TLspInactiveRegions.Regions(mProcessed, True, mIssues);
    Assert.AreEqual(1, Integer(Length(mRegions)));
    Assert.AreEqual(4, mRegions[0].Range.StartPos.Line);
    Assert.AreEqual('not FOO', mRegions[0].Condition);
    Assert.AreEqual(1, Integer(Length(mIssues)), 'fehlt.inc');
    Assert.AreEqual(7, mIssues[0].Range.StartPos.Line);
    // Ohne Resolver im Lauf keine Include-Befunde.
    mRegions := TLspInactiveRegions.Regions(mProcessed, False, mIssues);
    Assert.AreEqual(0, Integer(Length(mIssues)));
  finally
    mTree.Free;
  end;
end;

procedure TIncludeDefinesTests.CheckerUsesProjectAndIncludeDefines;
const
  cWin64Unit =
    'unit Ziel;'#10'interface'#10'implementation'#10'procedure X;'#10'begin'#10 +
    '{$IFDEF WIN64}'#10'  X;'#10'{$ELSE}'#10'  if then'#10'{$ENDIF}'#10'end;'#10'end.';

  function SyntaxFindings(const AText: string; const ASource: TCheckSource): Integer;
  var
    mFinding: TRuleFinding;
  begin
    Result := 0;
    for mFinding in TFileChecker.CheckText(nil, TServerSettings.Default, 'Ziel.pas', AText, ASource) do
    begin
      if mFinding.RuleId = cSyntaxRuleId then
      begin
        Inc(Result);
      end;
    end;
  end;

begin
  // Vorgabe Win32: der {$ELSE}-Zweig ist aktiv und kaputt.
  Assert.IsTrue(Length(TFileChecker.CheckText(nil, TServerSettings.Default, 'Ziel.pas', cWin64Unit)) > 0, 'Win32');
  Assert.AreEqual(0, SyntaxFindings(cWin64Unit, TCheckSource.Create(cMainFile,
    TPascalPreprocessor.PredefinedSymbols('Win64', 37), nil)), 'Win64');
  DefsText := '{$DEFINE FOO}';
  Assert.IsTrue(SyntaxFindings(cAccepted, TCheckSource.Default) > 0, 'ohne Include-Dateien');
  Assert.AreEqual(0, SyntaxFindings(cAccepted, TCheckSource.Create(cMainFile, nil, Resolver())), 'mit defs.inc');
end;

procedure TIncludeDefinesTests.InlayHintNamesUsedIncludeSymbols;
const
  cSource =
    'unit U;'#10 +                                          // 0
    'interface'#10 +                                        // 1
    '{$I defs.inc}'#10 +                                    // 2
    '{$IFDEF FOO}{$ENDIF}'#10 +                             // 3
    '{$IF Defined(BAR) and not Defined(GONE)}{$IFEND}'#10 + // 4
    'implementation'#10 +                                   // 5
    'end.';
var
  mTree: TSyntaxTree;
  mProcessed: TPreprocessorResult;
  mSettings: TInlayHintSettings;
  mHints: TArray<TInlayHint>;
  mJson: TJSONArray;
begin
  // UNUSED prüft die Unit nicht, GONE hebt die Include-Datei wieder auf.
  DefsText := '{$DEFINE FOO}'#10'{$DEFINE UNUSED}'#10'{$DEFINE GONE}'#10'{$DEFINE BAR}'#10'{$UNDEF GONE}';
  mTree := TPascalParser.ParseActive(cSource, TPascalPreprocessor.EditorOptions(nil, cMainFile, Resolver()), nil,
    mProcessed);
  try
    mSettings := TInlayHintSettings.Default;
    mSettings.ParameterNames := False;
    mSettings.InferredTypes := False;
    mSettings.EndMarkers := False;
    mHints := TLspInlayHints.Collect(TInlayHintSource.Create(nil, nil, mTree, cSource, cMainFile, nil),
      TTextRange.Create(0, 0, 7, 0), mSettings, mProcessed);
    Assert.AreEqual(1, Integer(Length(mHints)));
    Assert.AreEqual('definiert FOO, BAR', mHints[0].Text);
    Assert.AreEqual(2, mHints[0].Position.Line);
    Assert.AreEqual(13, mHints[0].Position.Character, 'hinter der Direktive');
    mJson := TLspInlayHints.ToJson(mHints);
    try
      Assert.AreEqual('defs.inc', mJson.Items[0].GetValue<string>('data.includeDefines.file'));
      Assert.AreEqual(2, Integer(mJson.Items[0].GetValue<TJSONArray>('data.includeDefines.names').Count));
      Assert.IsNull((mJson.Items[0] as TJSONObject).GetValue('kind'), 'ohne kind wie Endmarken');
    finally
      mJson.Free;
    end;
    // Außerhalb des Bereichs und abgeschaltet: nichts.
    Assert.AreEqual(0, Integer(Length(TLspInlayHints.IncludeDefines(mTree, mProcessed,
      TTextRange.Create(3, 0, 7, 0)))));
    mSettings.IncludeDefines := False;
    Assert.AreEqual(0, Integer(Length(TLspInlayHints.Collect(TInlayHintSource.Create(nil, nil, mTree,
      cSource, cMainFile, nil), TTextRange.Create(0, 0, 7, 0), mSettings, mProcessed))));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIncludeDefinesTests);

end.
