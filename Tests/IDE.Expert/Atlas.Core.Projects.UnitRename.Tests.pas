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
  Queue: TAtlasUnitRenameQueue;
  Items: TArray<TAtlasUnitRenameEvent>;
begin
  Queue := TAtlasUnitRenameQueue.Create;
  try
    Assert.IsTrue(Queue.Add(TAtlasUnitRenameEvent.Create('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas', 'C:\P\A.dproj')));
    // Dieselbe Unit in einem zweiten Projekt der Gruppe.
    Assert.IsFalse(Queue.Add(TAtlasUnitRenameEvent.Create('c:\p\kunden.pas', 'C:\P\KundenDaten.pas', 'C:\P\B.dproj')));
    Assert.IsFalse(Queue.Add(TAtlasUnitRenameEvent.Create('C:\P\Form.dfm', 'C:\P\Neu.dfm', 'C:\P\A.dproj')));
    Assert.IsTrue(Queue.Add(TAtlasUnitRenameEvent.Create('C:\P\Lager.pas', 'C:\P\Bestand.pas', 'C:\P\A.dproj')));
    Assert.AreEqual(2, Queue.Count);
    Items := Queue.Take;
    Assert.AreEqual(2, Integer(Length(Items)));
    Assert.AreEqual('C:\P\A.dproj', Items[0].ProjectFile);
    Assert.AreEqual('C:\P\Bestand.pas', Items[1].NewFile);
    Assert.AreEqual(0, Queue.Count);
  finally
    Queue.Free;
  end;
end;

procedure TAtlasUnitRenameTests.SourceFilesWithoutDuplicates;
var
  Files: TArray<string>;
begin
  Files := TAtlasUnitRename.SourceFiles(['C:\P\A.pas', 'C:\P\A.dfm', 'c:\p\a.pas', 'C:\P\Projekt.dpr', '',
    'C:\P\Projekt.dproj', 'C:\P\Defs.inc', 'C:\P\Paket.dpk']);
  Assert.AreEqual('C:\P\A.pas|C:\P\Projekt.dpr|C:\P\Defs.inc|C:\P\Paket.dpk', string.Join('|', Files));
end;

procedure TAtlasUnitRenameTests.ArgumentsCarryUris;
var
  Value: TJSONValue;
  List: TJSONArray;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasUnitRename.Arguments('C:\P\Kunden.pas', 'C:\P\KundenDaten.pas',
    ['C:\P\Kasse.pas', 'C:\P\Kasse.dfm', 'C:\P\Projekt.dpr']));
  try
    Assert.IsTrue(Value is TJSONArray);
    List := TJSONArray(Value);
    Assert.AreEqual(3, Integer(List.Count));
    Assert.AreEqual(TLspSession.PathToUri('C:\P\Kunden.pas'), List.Items[0].Value);
    Assert.AreEqual(TLspSession.PathToUri('C:\P\KundenDaten.pas'), List.Items[1].Value);
    Assert.AreEqual(2, Integer((List.Items[2] as TJSONArray).Count), 'ohne .dfm');
    Assert.AreEqual(TLspSession.PathToUri('C:\P\Projekt.dpr'), (List.Items[2] as TJSONArray).Items[1].Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasUnitRenameTests.ReadsAnswerAndCountsPerScope;
var
  Value: TJSONValue;
  Answer: TAtlasUnitRenameAnswer;
  Text: string;
begin
  Value := TJSONObject.ParseJSONValue('{"enabled":false}');
  try
    Assert.IsFalse(TAtlasUnitRename.ReadAnswer(Value).Enabled, 'abgeschaltet');
  finally
    Value.Free;
  end;
  Assert.IsFalse(TAtlasUnitRename.ReadAnswer(nil).Enabled, 'ohne Antwort');
  Text := '{"enabled":true,"old":"Kunden","new":"KundenDaten","count":3,"edit":{"documentChanges":[' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\P\Kasse.pas') + '","version":null},"edits":[]},' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\P\Lager.pas') + '","version":null},"edits":[]},' +
    '{"textDocument":{"uri":"' + TLspSession.PathToUri('C:\Q\Bericht.pas') + '","version":null},"edits":[]}]}}';
  Value := TJSONObject.ParseJSONValue(Text);
  try
    Answer := TAtlasUnitRename.ReadAnswer(Value);
  finally
    Value.Free;
  end;
  Assert.IsTrue(Answer.Enabled);
  Assert.AreEqual('Kunden', Answer.OldName);
  Assert.AreEqual('KundenDaten', Answer.NewName);
  Assert.AreEqual(3, Integer(Length(Answer.Files)));
  // Laufwerksbuchstabe kommt klein aus der URI zurück.
  Assert.IsTrue(SameText('C:\P\Lager.pas', Answer.Files[1]), Answer.Files[1]);
  // Projekt: Kasse und Lager; Gruppe: alle drei.
  Assert.AreEqual(2, TAtlasUnitRename.CountIn(Answer, ['c:\p\kasse.pas', 'C:\P\Lager.pas', 'C:\P\Projekt.dpr']));
  Assert.AreEqual(3, TAtlasUnitRename.CountIn(Answer, ['C:\P\Kasse.pas', 'C:\P\Lager.pas', 'C:\Q\Bericht.pas']));
  Answer := Default(TAtlasUnitRenameAnswer);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRenameTests);

end.
