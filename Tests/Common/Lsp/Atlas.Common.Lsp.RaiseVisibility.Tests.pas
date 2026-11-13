unit Atlas.Common.Lsp.RaiseVisibility.Tests;

// Tests für „Sichtbarkeit anheben“ über das Protokoll (#2108): Code-Aktionen auf
// der Deklaration (nur Anheben) und der Befehl für die Vervollständigung (auch
// „Eigenschaft anlegen“) mit WorkspaceEdit für die Datei der Deklaration.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspRaiseVisibilityTests = class
  public
    [Test]
    procedure ActionsOnDeclaration;
    [Test]
    procedure CommandListsPropertyAndRaise;
    [Test]
    procedure CommandWithoutMemberIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.RaiseVisibility;

const
  cUri = 'file:///C:/P/Zaehler.pas';
  Source =
    'unit Zaehler;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TZaehler = class'#10 +
    '  private'#10 +
    '    FEintraege: Integer;'#10 +                     // 5
    '  public'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TZaehler.Run;'#10'begin'#10'end;'#10 +
    'end.'#10;

/// <summary>Titel der Code-Aktionen in AActions, mit | getrennt.</summary>
function Titles(AActions: TJSONArray): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  for mItem in AActions do
  begin
    Result := Result + (mItem as TJSONObject).GetValue<string>('title') + '|';
  end;
end;

procedure TLspRaiseVisibilityTests.ActionsOnDeclaration;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
  mItem: TJSONObject;
begin
  mTree := TSyntaxTreeCache.Parse(Source);
  try
    mActions := TLspRaiseVisibility.Actions(cUri, Source, mTree, TTextRange.Create(TTextPosition.Create(5, 6),
      TTextPosition.Create(5, 6)));
    try
      Assert.AreEqual(2, Integer(Length(mActions)));
      Assert.AreEqual('Sichtbarkeit von FEintraege auf protected anheben', mActions[0].GetValue<string>('title'));
      Assert.AreEqual('refactor.rewrite', mActions[0].GetValue<string>('kind'));
      Assert.IsTrue(mActions[1].GetValue('edit') is TJSONObject, mActions[1].ToJSON);
    finally
      for mItem in mActions do
      begin
        mItem.Free;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspRaiseVisibilityTests.CommandListsPropertyAndRaise;
var
  mAnswer: TJSONArray;
  mChanges: TJSONObject;
begin
  mAnswer := TLspRaiseVisibility.Execute(cUri, Source, TTextPosition.Create(5, 4), 'FEintraege');
  try
    Assert.AreEqual('Eigenschaft Eintraege in TZaehler anlegen (nur lesen)|' +
      'Eigenschaft Eintraege in TZaehler anlegen (lesen und schreiben)|' +
      'Sichtbarkeit von FEintraege auf protected anheben|Sichtbarkeit von FEintraege auf public anheben|',
      Titles(mAnswer));
    mChanges := (mAnswer.Items[0] as TJSONObject).GetValue<TJSONObject>('edit').GetValue<TJSONObject>('changes');
    Assert.IsTrue(mChanges.GetValue(cUri) is TJSONArray, mChanges.ToJSON);
    Assert.IsTrue(Pos('property Eintraege: Integer read FEintraege;', mChanges.ToJSON) > 0, mChanges.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspRaiseVisibilityTests.CommandWithoutMemberIsEmpty;
var
  mAnswer: TJSONArray;
begin
  mAnswer := TLspRaiseVisibility.Execute(cUri, Source, TTextPosition.Create(7, 4), 'Run');
  try
    Assert.AreEqual(0, mAnswer.Count, 'public');
  finally
    mAnswer.Free;
  end;
  mAnswer := TLspRaiseVisibility.Execute(cUri, 'unit Leer;'#10'interface'#10'implementation'#10'end.'#10,
    TTextPosition.Create(1, 0), 'FEintraege');
  try
    Assert.AreEqual(0, mAnswer.Count, 'keine Klasse');
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspRaiseVisibilityTests);

end.
