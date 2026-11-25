unit Atlas.Common.Architecture.Adapters.GroupFiles.Tests;

// Tests der Projektdateien für projektweite Regeln (#1102): Reihenfolge der
// Projekte, NameIn über die Verwendungen des Index und über den Text
// (Direktivenwörter, Units ohne Verwendungen, Include-Dateien, jede Datei nur
// einmal gelesen), Projektart und
// Testprojekte aus dem Hauptquelltext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectGroupFilesTests = class
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
    procedure NameInReadsEachFileOnce;
    [Test]
    procedure CompleteAsksHost;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Architecture.Adapters.GroupFiles;

function Project(const AFileName: string; const ASources: TArray<string>): TGroupProject;
begin
  Result := Default(TGroupProject);
  Result.FileName := AFileName;
  Result.Kind := TGroupProjectKind.Application;
  Result.Sources := ASources;
end;

const
  cUnitA = 'unit A;'#10'interface'#10'procedure Laden;'#10'implementation'#10'procedure Laden;'#10'begin'#10 +
    '  Speichern; // Kommentar: Vergessen'#10'  Writeln(''Vergessen'');'#10'end;'#10'end.';

function Files(const AIndex: ISymbolIndex; const ATexts: TDictionary<string, string>;
  const AComplete: Boolean): IProjectGroupFiles;
begin
  Result := TProjectGroupFiles.Create([Project('C:\P\App.dproj', ['C:\P\App.dpr', 'C:\P\A.pas']),
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
      begin
        AReason := 'Index läuft';
      end;
    end);
end;

{ TProjectGroupFilesTests }

procedure TProjectGroupFilesTests.ProjectsOfPutsOwnProjectsFirst;
var
  mFound: TArray<TGroupProject>;
begin
  mFound := Files(nil, nil, True).ProjectsOf('C:\P\A.pas', False);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('C:\P\App.dproj', mFound[0].FileName);
  Assert.AreEqual('C:\P\Dll.dproj', mFound[1].FileName);
  mFound := Files(nil, nil, True).ProjectsOf('c:\p\a.pas', True);
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('C:\P\Werkzeug.dproj', mFound[2].FileName);
  Assert.AreEqual(0, Integer(Length(Files(nil, nil, True).ProjectsOf('C:\Fremd.pas', True))));
end;

procedure TProjectGroupFilesTests.NameInUsesIndexUsages;
var
  mIndex: ISymbolIndex;
  mProvider: IProjectGroupFiles;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitA, 'C:\P\A.pas', nil, nil, True));
  // Ohne Texte: die Antwort kommt allein aus dem Index.
  mProvider := Files(mIndex, nil, True);
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('C:\P\A.pas', 'speichern'));
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Vergessen'), 'Kommentar und String');
  // Die eigene Deklaration ist keine Verwendung, Laden steht aber im Rumpf-Kopf als Deklaration.
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Laden'));
end;

procedure TProjectGroupFilesTests.NameInFallsBackToText;
var
  mIndex: ISymbolIndex;
  mTexts: TDictionary<string, string>;
  mProvider: IProjectGroupFiles;
begin
  mIndex := TSymbolIndex.Create;
  // Ohne Verwendungen im Index.
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitA, 'C:\P\A.pas', nil));
  mTexts := TDictionary<string, string>.Create;
  try
    mProvider := Files(mIndex, mTexts, True);
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Unknown, mProvider.NameIn('C:\P\A.pas', 'Speichern'), 'nicht lesbar');
    mTexts.Add('C:\P\A.pas', cUnitA + #10'// Override'#10);
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('C:\P\A.pas', 'Speichern'));
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Vergessen'));
    // Direktivenwörter zählt der Index nicht; im Kommentar zählen sie auch nicht.
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Override'));
    mTexts.Add('C:\P\App.dpr', 'program App;'#10'begin'#10'  Override := 1;'#10'end.');
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('C:\P\App.dpr', 'override'));
    mProvider := nil;
  finally
    mTexts.Free;
  end;
end;

procedure TProjectGroupFilesTests.NameInReadsIncludes;
var
  mIndex: ISymbolIndex;
  mTexts: TDictionary<string, string>;
  mProvider: IProjectGroupFiles;
  mIndexed: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndexed := TIndexExtractor.ExtractText(cUnitA, 'C:\P\A.pas', nil, nil, True);
  mIndexed.Includes := ['C:\P\Teil.inc'];
  mIndex.AddUnit(mIndexed);
  mTexts := TDictionary<string, string>.Create;
  try
    mTexts.Add('C:\P\A.pas', cUnitA);
    mProvider := Files(mIndex, mTexts, True);
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Unknown, mProvider.NameIn('C:\P\A.pas', 'Drucken'), 'Include fehlt');
    mTexts.Add('C:\P\Teil.inc', 'procedure X;'#10'begin'#10'  Drucken;'#10'end;');
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('C:\P\A.pas', 'Drucken'));
    Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Fehlt'));
    mProvider := nil;
  finally
    mTexts.Free;
  end;
end;

procedure TProjectGroupFilesTests.NameInReadsEachFileOnce;
var
  mReads: Integer;
  mRead: TProjectReadText;
  mProvider: IProjectGroupFiles;
begin
  // Ohne Verwendungen im Index (ausgelagert): NameIn darf die Datei nicht für jeden Namen neu lesen und parsen;
  // unused-public-member fragt je Mitglied alle Dateien der Gruppe, der Prüflauf stünde sonst still.
  mReads := 0;
  mRead :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Inc(mReads);
      AText := cUnitA;
      Result := True;
    end;
  mProvider := TProjectGroupFiles.Create([Project('C:\P\App.dproj', ['C:\P\A.pas'])], nil, mRead, nil);
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('C:\P\A.pas', 'Speichern'));
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Present, mProvider.NameIn('c:\p\a.pas', 'LADEN'));
  Assert.AreEqual<TNameAnswer>(TNameAnswer.Absent, mProvider.NameIn('C:\P\A.pas', 'Vergessen'));
  Assert.AreEqual(1, mReads);
  mProvider := nil;
  mRead := nil;
end;

procedure TProjectGroupFilesTests.CompleteAsksHost;
var
  mReason: string;
begin
  Assert.IsTrue(Files(nil, nil, True).Complete(mReason));
  Assert.AreEqual('', mReason);
  Assert.IsFalse(Files(nil, nil, False).Complete(mReason));
  Assert.AreEqual('Index läuft', mReason);
  Assert.IsTrue((TProjectGroupFiles.Create(nil, nil, nil, nil) as IProjectGroupFiles).Complete(mReason));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectGroupFilesTests);

end.
