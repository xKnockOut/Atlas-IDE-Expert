unit Atlas.Common.Lsp.IndexRefresh.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Index der aktiven Unit nach der Tipp-Pause (#492).</summary>
  [TestFixture]
  TLspIndexRefreshTests = class
  public
    [Test]
    procedure AppliesPascalSourcesOnly;
    [Test]
    procedure LastTextWinsAfterPause;
    [Test]
    procedure UsesChangesOnlyForUsesLists;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Lsp.IndexRefresh;

procedure TLspIndexRefreshTests.AppliesPascalSourcesOnly;
var
  mRefresh: TLspIndexRefresh;
  mApplied: string;
begin
  mApplied := '';
  mRefresh := TLspIndexRefresh.Create(0,
    procedure(const AFileName, AText: string)
    begin
      mApplied := mApplied + ExtractFileName(AFileName) + '=' + AText + ';';
    end);
  try
    mRefresh.Changed('C:\P\A.pas', 'a');
    mRefresh.Changed('C:\P\B.dpr', 'b');
    mRefresh.Changed('C:\P\C.inc', 'c');
    mRefresh.Changed('C:\P\atlas.json', 'd');
  finally
    mRefresh.Free;
  end;
  Assert.AreEqual('A.pas=a;B.dpr=b;', mApplied);
end;

procedure TLspIndexRefreshTests.LastTextWinsAfterPause;
var
  mRefresh: TLspIndexRefresh;
  mDone: TEvent;
  mApplied: string;
  mCount: Integer;
begin
  mDone := TEvent.Create(nil, True, False, '');
  try
    mCount := 0;
    mRefresh := TLspIndexRefresh.Create(50,
      procedure(const AFileName, AText: string)
      begin
        mApplied := AText;
        TInterlocked.Increment(mCount);
        mDone.SetEvent;
      end);
    try
      mRefresh.Changed('C:\P\A.pas', 'eins');
      mRefresh.Changed('C:\P\A.pas', 'zwei');
      mRefresh.Changed('C:\P\A.pas', 'drei');
      Assert.AreEqual<TWaitResult>(wrSignaled, mDone.WaitFor(2000), 'nach der Pause übernommen');
      Sleep(100);
    finally
      mRefresh.Free;
    end;
    Assert.AreEqual('drei', mApplied);
    Assert.AreEqual(1, mCount, 'nur einmal nach der Pause');
  finally
    mDone.Free;
  end;
  mApplied := '';
end;

procedure TLspIndexRefreshTests.UsesChangesOnlyForUsesLists;
var
  mChanges: TLspUsesChanges;
begin
  mChanges := TLspUsesChanges.Create;
  try
    Assert.IsTrue(mChanges.Changed('C:\P\A.pas', 'unit A; interface uses B; implementation end.'), 'erster Stand');
    Assert.IsFalse(mChanges.Changed('C:\P\A.pas', 'unit A; interface uses B; implementation var X: Integer; end.'),
      'Änderung außerhalb der uses');
    Assert.IsTrue(mChanges.Changed('c:\p\a.pas', 'unit A; interface uses B, C; implementation end.'), 'Eintrag ergänzt');
    Assert.IsTrue(mChanges.Changed('C:\P\A.pas', 'unit A; interface implementation uses B, C; end.'),
      'zwischen interface und implementation verschoben');
    mChanges.Forget('C:\P\A.pas');
    Assert.IsTrue(mChanges.Changed('C:\P\A.pas', 'unit A; interface implementation uses B, C; end.'),
      'nach dem Schließen wieder erster Stand');
    Assert.AreEqual('I:B|M:C', TLspUsesChanges.Signature('unit A; interface uses B; implementation uses C; end.'));
  finally
    mChanges.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIndexRefreshTests);

end.