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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Lsp.IndexRefresh;

procedure TLspIndexRefreshTests.AppliesPascalSourcesOnly;
var
  Refresh: TLspIndexRefresh;
  Applied: string;
begin
  Applied := '';
  Refresh := TLspIndexRefresh.Create(0,
    procedure(const AFileName, AText: string)
    begin
      Applied := Applied + ExtractFileName(AFileName) + '=' + AText + ';';
    end);
  try
    Refresh.Changed('C:\P\A.pas', 'a');
    Refresh.Changed('C:\P\B.dpr', 'b');
    Refresh.Changed('C:\P\C.inc', 'c');
    Refresh.Changed('C:\P\atlas.json', 'd');
  finally
    Refresh.Free;
  end;
  Assert.AreEqual('A.pas=a;B.dpr=b;', Applied);
end;

procedure TLspIndexRefreshTests.LastTextWinsAfterPause;
var
  Refresh: TLspIndexRefresh;
  Done: TEvent;
  Applied: string;
  Count: Integer;
begin
  Done := TEvent.Create(nil, True, False, '');
  try
    Count := 0;
    Refresh := TLspIndexRefresh.Create(50,
      procedure(const AFileName, AText: string)
      begin
        Applied := AText;
        TInterlocked.Increment(Count);
        Done.SetEvent;
      end);
    try
      Refresh.Changed('C:\P\A.pas', 'eins');
      Refresh.Changed('C:\P\A.pas', 'zwei');
      Refresh.Changed('C:\P\A.pas', 'drei');
      Assert.AreEqual(wrSignaled, Done.WaitFor(2000));
      Sleep(100);
    finally
      Refresh.Free;
    end;
    Assert.AreEqual('drei', Applied);
    Assert.AreEqual(1, Count, 'nur einmal nach der Pause');
  finally
    Done.Free;
  end;
  Applied := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIndexRefreshTests);

end.
