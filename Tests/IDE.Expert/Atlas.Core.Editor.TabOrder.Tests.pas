unit Atlas.Core.Editor.TabOrder.Tests;

// Reihenfolge der Reiter aus ihren Beschriftungen (Fortsetzen der Willkommensseite, IDE-Zustand #2050).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorTabOrderTests = class
  public
    [Test]
    procedure OrderFollowsTabCaptions;
    [Test]
    procedure WithoutCaptionsKeepsBufferOrder;
    [Test]
    procedure CaptionNameDropsMarks;
  end;

implementation

uses
  Atlas.Core.Editor.TabOrder;

const
  cRoot = 'C:\Quellen';

function Path(const AName: string): string;
begin
  Result := cRoot + '\' + AName;
end;

function Files: TArray<string>;
begin
  Result := [Path('A.pas'), Path('B.pas'), Path('Sub\B.pas'), Path('C.pas'), Path('Projekt.dpr')];
end;

procedure TAtlasEditorTabOrderTests.OrderFollowsTabCaptions;
var
  mOrdered: TArray<string>;
begin
  mOrdered := TAtlasEditorTabOrder.Order(Files, ['Willkommensseite', 'C.pas', '*B.pas', 'Projekt', 'B.pas*', 'A']);
  Assert.AreEqual(5, Integer(Length(mOrdered)));
  Assert.AreEqual(Path('C.pas'), mOrdered[0]);
  Assert.AreEqual(Path('B.pas'), mOrdered[1], 'Markierung „*“ zählt nicht');
  Assert.AreEqual(Path('Projekt.dpr'), mOrdered[2], 'Beschriftung ohne Endung');
  Assert.AreEqual(Path('Sub\B.pas'), mOrdered[3], 'gleicher Name: der nächste noch freie');
  Assert.AreEqual(Path('A.pas'), mOrdered[4]);
end;

procedure TAtlasEditorTabOrderTests.WithoutCaptionsKeepsBufferOrder;
var
  mOrdered: TArray<string>;
begin
  mOrdered := TAtlasEditorTabOrder.Order(Files, nil);
  Assert.AreEqual(5, Integer(Length(mOrdered)));
  Assert.AreEqual(Path('A.pas'), mOrdered[0], 'ohne Beschriftungen die Reihenfolge der Puffer');
  Assert.AreEqual(Path('Projekt.dpr'), mOrdered[4]);
end;

procedure TAtlasEditorTabOrderTests.CaptionNameDropsMarks;
begin
  Assert.AreEqual('Kunde.pas', TAtlasEditorTabOrder.CaptionName(' *&Kunde.pas* '));
  Assert.AreEqual('', TAtlasEditorTabOrder.CaptionName('**'));
end;

end.
