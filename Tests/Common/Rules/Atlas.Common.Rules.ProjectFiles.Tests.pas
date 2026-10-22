unit Atlas.Common.Rules.ProjectFiles.Tests;

// Tests der Projektdateien für projektweite Regeln (#1102): Reihenfolge der
// Projekte, NameIn über die Verwendungen des Index und über den Text
// (Direktivenwörter, Units ohne Verwendungen, Include-Dateien), Projektart und
// Testprojekte aus dem Hauptquelltext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleProjectFilesTests = class
  public
    [Test]
    procedure ProjectsOfPutsOwnProjectsFirst;
    [Test]
    procedure NameInUsesIndexUsages;
    [Test]
    procedure NameInFallsBackToText;
    [Test]
    procedure NameInReadsIncludes;
    [Test]
    procedure CompleteAsksHost;
    [Test]
    procedure KindAndTestsFromMainSource;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.ProjectFiles;

function Project(const AFileName: string; const ASources: TArray<string>): TRuleProject;
begin
  Result := Default(TRuleProject);
  Result.FileName := AFileName;
  Result.Kind := TRuleProjectKind.Application;
  Result.Sources := ASources;
end;

const
  UnitA = 'unit A;'#10'interface'#10'procedure Laden;'#10'implementation'#10'procedure Laden;'#10'begin'#10 +
    '  Speichern; // Kommentar: Vergessen'#10'  Writeln(''Vergessen'');'#10'end;'#10'end.';

function Files(const AIndex: ISymbolIndex; const ATexts: TDictionary<string, string>;
  const AComplete: Boolean): IRuleProjectFiles;
begin
  Result := TRuleProjectFiles.Create([Project('C:\P\App.dproj', ['C:\P\App.dpr', 'C:\P\A.pas']),
    Project('C:\P\Werkzeug.dproj', ['C:\P\Werkzeug.dpr']), Project('C:\P\Dll.dproj', ['C:\P\Dll.dpr', 'C:\P\A.pas'])],
    AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := (ATexts <> nil) and ATexts.TryGetValue(AFileName, AText);
    end,
    function(out AReason: string): Boolean
    begin
      Result := AComplete;
      if not Result then
        AReason := 'Index läuft';
    end);
end;

procedure TRuleProjectFilesTests.ProjectsOfPutsOwnProjectsFirst;
var
  Found: TArray<TRuleProject>;
begin
  Found := Files(nil, nil, True).ProjectsOf('C:\P\A.pas', False);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('C:\P\App.dproj', Found[0].FileName);
  Assert.AreEqual('C:\P\Dll.dproj', Found[1].FileName);
  Found := Files(nil, nil, True).ProjectsOf('c:\p\a.pas', True);
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('C:\P\Werkzeug.dproj', Found[2].FileName);
  Assert.AreEqual(0, Integer(Length(Files(nil, nil, True).ProjectsOf('C:\Fremd.pas', True))));
end;

procedure TRuleProjectFilesTests.NameInUsesIndexUsages;
var
  Index: ISymbolIndex;
  Provider: IRuleProjectFiles;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitA, 'C:\P\A.pas', nil, nil, True));
  // Ohne Texte: die Antwort kommt allein aus dem Index.
  Provider := Files(Index, nil, True);
  Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Present, Provider.NameIn('C:\P\A.pas', 'speichern'));
  Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Absent, Provider.NameIn('C:\P\A.pas', 'Vergessen'), 'Kommentar und String');
  // Die eigene Deklaration ist keine Verwendung, Laden steht aber im Rumpf-Kopf als Deklaration.
  Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Absent, Provider.NameIn('C:\P\A.pas', 'Laden'));
end;

procedure TRuleProjectFilesTests.NameInFallsBackToText;
var
  Index: ISymbolIndex;
  Texts: TDictionary<string, string>;
  Provider: IRuleProjectFiles;
begin
  Index := TSymbolIndex.Create;
  // Ohne Verwendungen im Index.
  Index.AddUnit(TIndexExtractor.ExtractText(UnitA, 'C:\P\A.pas', nil));
  Texts := TDictionary<string, string>.Create;
  try
    Provider := Files(Index, Texts, True);
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Unknown, Provider.NameIn('C:\P\A.pas', 'Speichern'), 'nicht lesbar');
    Texts.Add('C:\P\A.pas', UnitA + #10'// Override'#10);
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Present, Provider.NameIn('C:\P\A.pas', 'Speichern'));
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Absent, Provider.NameIn('C:\P\A.pas', 'Vergessen'));
    // Direktivenwörter zählt der Index nicht; im Kommentar zählen sie auch nicht.
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Absent, Provider.NameIn('C:\P\A.pas', 'Override'));
    Texts.Add('C:\P\App.dpr', 'program App;'#10'begin'#10'  Override := 1;'#10'end.');
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Present, Provider.NameIn('C:\P\App.dpr', 'override'));
    Provider := nil;
  finally
    Texts.Free;
  end;
end;

procedure TRuleProjectFilesTests.NameInReadsIncludes;
var
  Index: ISymbolIndex;
  Texts: TDictionary<string, string>;
  Provider: IRuleProjectFiles;
  Indexed: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  Indexed := TIndexExtractor.ExtractText(UnitA, 'C:\P\A.pas', nil, nil, True);
  Indexed.Includes := ['C:\P\Teil.inc'];
  Index.AddUnit(Indexed);
  Texts := TDictionary<string, string>.Create;
  try
    Texts.Add('C:\P\A.pas', UnitA);
    Provider := Files(Index, Texts, True);
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Unknown, Provider.NameIn('C:\P\A.pas', 'Drucken'), 'Include fehlt');
    Texts.Add('C:\P\Teil.inc', 'procedure X;'#10'begin'#10'  Drucken;'#10'end;');
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Present, Provider.NameIn('C:\P\A.pas', 'Drucken'));
    Assert.AreEqual<TRuleNameAnswer>(TRuleNameAnswer.Absent, Provider.NameIn('C:\P\A.pas', 'Fehlt'));
    Provider := nil;
  finally
    Texts.Free;
  end;
end;

procedure TRuleProjectFilesTests.CompleteAsksHost;
var
  Reason: string;
begin
  Assert.IsTrue(Files(nil, nil, True).Complete(Reason));
  Assert.AreEqual('', Reason);
  Assert.IsFalse(Files(nil, nil, False).Complete(Reason));
  Assert.AreEqual('Index läuft', Reason);
  Assert.IsTrue(TRuleProjectFiles.Create(nil, nil, nil, nil).Complete(Reason));
end;

procedure TRuleProjectFilesTests.KindAndTestsFromMainSource;
begin
  Assert.AreEqual<TRuleProjectKind>(TRuleProjectKind.Application, TRuleProjectFiles.KindOfSource('App.dpr',
    '{ Kopf }'#10'program App;'#10'begin'#10'end.'));
  Assert.AreEqual<TRuleProjectKind>(TRuleProjectKind.Library_, TRuleProjectFiles.KindOfSource('Dll.dpr', 'library Dll;'#10'begin'#10'end.'));
  Assert.AreEqual<TRuleProjectKind>(TRuleProjectKind.Package, TRuleProjectFiles.KindOfSource('Pak.dpk', ''));
  Assert.AreEqual<TRuleProjectKind>(TRuleProjectKind.Package, TRuleProjectFiles.KindOfSource('Pak.dpr', 'package Pak;'#10'end.'));
  Assert.AreEqual<TRuleProjectKind>(TRuleProjectKind.Unknown, TRuleProjectFiles.KindOfSource('X.pas', 'unit X;'));
  Assert.IsTrue(TRuleProjectFiles.IsTestSource('program T;'#10'uses'#10'  DUnitX.TestFramework;'#10'begin'#10'end.'));
  Assert.IsFalse(TRuleProjectFiles.IsTestSource('program App;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleProjectFilesTests);

end.
