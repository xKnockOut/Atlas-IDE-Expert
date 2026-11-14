unit Atlas.Core.Projects.UnitRename.Tests;

// Tests für uses nachziehen nach dem Umbenennen einer Unit (#512), Plugin-Kern:
// Erkennung, Warteschlange ohne Doppelte, Dateien des Bereichs, Argumente und
// Antwort des Servers samt Zählung je Bereich.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUnitRenameTests = class
  public
    [Test]
    procedure RecognizesOnlyUnitRenames;
    [Test]
    procedure QueueKeepsEachRenameOnce;
    [Test]
    procedure SourceFilesWithoutDuplicates;
    [Test]
    procedure ArgumentsCarryUris;
    [Test]
    procedure ReadsAnswerAndCountsPerScope;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Projects.UnitRename;

procedure TAtlasUnitRenameTests.RecognizesOnlyUnitRenames;
begin
  Assert.IsTrue(TAtlasUnitRename.IsUnitRename('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas'));
  Assert.IsFalse(TAtlasUnitRename.IsUnitRename('C:\P\Kunden.pas', 'C:\P\KUNDEN.pas'), 'nur Schreibweise');
  Assert.IsFalse(TAtlasUnitRename.IsUnitRename('C:\P\Kunden.dfm', 'C:\P\KundenDaten.dfm'), 'Formulardatei');
  Assert.IsFalse(TAtlasUnitRename.IsUnitRename('C:\P\Projekt.dpr', 'C:\P\Neu.dpr'), 'Programm');
  Assert.AreEqual('KundenDaten', TAtlasUnitRename.UnitNameOf('C:\P\KundenDaten.pas'));
end;

procedure TAtlasUnitRenameTests.QueueKeepsEachRenameOnce;
var
  mQueue: TAtlasUnitRenameQueue;
  mItems: TArray<TAtlasUnitRenameEvent>;
begin
  mQueue := TAtlasUnitRenameQueue.Create;
  try
    Assert.IsTrue(mQueue.Add(TAtlasUnitRenameEvent.Create('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas', 'C:\P\A.dproj')));
    // Dieselbe Unit in einem zweiten Projekt der Gruppe.
    Assert.IsFalse(mQueue.Add(TAtlasUnitRenameEvent.Create('c:\p\kunden.pas', 'C:\P\KundenDaten.pas', 'C:\P\B.dproj')));
    Assert.IsFalse(mQueue.Add(TAtlasUnitRenameEvent.Create('C:\P\Form.dfm', 'C:\P\Neu.dfm', 'C:\P\A.dproj')));
    Assert.IsTrue(mQueue.Add(TAtlasUnitRenameEvent.Create('C:\P\Lager.pas', 'C:\P\Bestand.pas', 'C:\P\A.dproj')));
    Assert.AreEqual(2, Integer(mQueue.Count));
    mItems := mQueue.Take;
    Assert.AreEqual(2, Integer(Length(mItems)));
    Assert.AreEqual('C:\P\A.dproj', mItems[0].ProjectFile);
    Assert.AreEqual('C:\P\Bestand.pas', mItems[1].NewFile);
    Assert.AreEqual(0, Integer(mQueue.Count));
  finally
    mQueue.Free;
  end;
end;

procedure TAtlasUnitRenameTests.SourceFilesWithoutDuplicates;
var
  mFiles: TArray<string>;
begin
  mFiles := TAtlasUnitRename.SourceFiles(['C:\P\A.pas', 'C:\P\A.dfm', 'c:\p\a.pas', 'C:\P\Projekt.dpr', '',
    'C:\P\Projekt.dproj', 'C:\P\Defs.inc', 'C:\P\Paket.dpk']);
  Assert.AreEqual('C:\P\A.pas|C:\P\Projekt.dpr|C:\P\Defs.inc|C:\P\Paket.dpk', string.Join('|', mFiles));
end;

procedure TAtlasUnitRenameTests.ArgumentsCarryUris;
var
  mValue: TJSONValue;
  mList: TJSONArray;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasUnitRename.Arguments('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas',
    ['C:\P\Kasse.pas', 'C:\P\Kasse.dfm', 'C:\P\Projekt.dpr']));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mList := TJSONArray(mValue);
    Assert.AreEqual(3, Integer(mList.Count));
    Assert.AreEqual(TLspSession.PathToUri('C:\P\Kunden.pas'), mList.Items[0].Value);
    Assert.AreEqual(TLspSession.PathToUri('C:\P\KundenDaten.pas'), mList.Items[1].Value);
    Assert.AreEqual(2, Integer((mList.Items[2] as TJSONArray).Count), 'ohne .dfm');
    Assert.AreEqual(TLspSession.PathToUri('C:\P\Projekt.dpr'), (mList.Items[2] as TJSONArray).Items[1].Value);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasUnitRenameTests.ReadsAnswerAndCountsPerScope;
var
  mValue: TJSONValue;
  mAnswer: TAtlasUnitRenameAnswer;
  mText: string;
begin
  mValue := TJSONObject.ParseJSONValue('{"enabled":false}');
  try
    Assert.IsFalse(TAtlasUnitRename.ReadAnswer(mValue).Enabled, 'abgeschaltet');
  finally
    mValue.Free;
  end;
  Assert.IsFalse(TAtlasUnitRename.ReadAnswer(nil).Enabled, 'ohne Antwort');
  mText := '{"enabled":true,"old":"Kunden","new":"KundenDaten","count":3,"edit":{"documentChanges":[' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\P\Kasse.pas') + '","version":null},"edits":[]},' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\P\Lager.pas') + '","version":null},"edits":[]},' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\Q\Bericht.pas') + '","version":null},"edits":[]}]}}';
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    mAnswer := TAtlasUnitRename.ReadAnswer(mValue);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mAnswer.Enabled);
  Assert.AreEqual('Kunden', mAnswer.OldName);
  Assert.AreEqual('KundenDaten', mAnswer.NewName);
  Assert.AreEqual(3, Integer(Length(mAnswer.Files)));
  // Laufwerksbuchstabe kommt klein aus der URI zurück.
  Assert.IsTrue(SameText('C:\P\Lager.pas', mAnswer.Files[1]), mAnswer.Files[1]);
  // Projekt: Kasse und Lager; Gruppe: alle drei.
  Assert.AreEqual(2, TAtlasUnitRename.CountIn(mAnswer, ['c:\p\kasse.pas', 'C:\P\Lager.pas', 'C:\P\Projekt.dpr']));
  Assert.AreEqual(3, TAtlasUnitRename.CountIn(mAnswer, ['C:\P\Kasse.pas', 'C:\P\Lager.pas', 'C:\Q\Bericht.pas']));
  mAnswer := Default(TAtlasUnitRenameAnswer);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRenameTests);

end.
