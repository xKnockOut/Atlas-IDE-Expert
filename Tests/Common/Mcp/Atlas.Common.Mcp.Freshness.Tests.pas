unit Atlas.Common.Mcp.Freshness.Tests;

// Tests für den aktuellen Index im MCP-Modus (#48).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpFreshnessTests = class
  public
    [Test]
    procedure ReportsChangedCreatedAndDeleted;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Mcp.Freshness;

type
  TStampFileSystem = class(TInterfacedObject, IIndexFileSystem)
  public
    Stamps: TDictionary<string, Int64>;
    constructor Create;
    destructor Destroy; override;
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
  end;

constructor TStampFileSystem.Create;
begin
  inherited Create;
  Stamps := TDictionary<string, Int64>.Create;
end;

destructor TStampFileSystem.Destroy;
begin
  Stamps.Free;
  inherited;
end;

function TStampFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  Result := Stamps.TryGetValue(AFileName, AStamp);
end;

function TStampFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TStampFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := False;
end;

function TStampFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := False;
end;

function TStampFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
begin
  AError := 'nur Zeitstempel';
  Result := False;
end;

function TStampFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  Result := nil;
end;

procedure TMcpFreshnessTests.ReportsChangedCreatedAndDeleted;
var
  Index: ISymbolIndex;
  FileSystem: TStampFileSystem;
  FileSystemRef: IIndexFileSystem;
  UnitIndex: TUnitIndex;
  Changes: TArray<TFileChange>;
  Text: string;
  Change: TFileChange;
begin
  Index := TSymbolIndex.Create;
  for Text in ['A', 'B', 'C'] do
  begin
    UnitIndex := Default(TUnitIndex);
    UnitIndex.UnitName := Text;
    UnitIndex.FileName := 'C:\P\' + Text + '.pas';
    UnitIndex.Stamp := 10;
    Index.AddUnit(UnitIndex);
  end;
  FileSystem := TStampFileSystem.Create;
  FileSystemRef := FileSystem;
  FileSystem.Stamps.Add('C:\P\A.pas', 10);
  FileSystem.Stamps.Add('C:\P\B.pas', 11);
  FileSystem.Stamps.Add('C:\P\D.pas', 5);
  Changes := TMcpFreshness.Changes(Index, FileSystemRef, ['C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas', 'C:\P\D.pas']);
  Text := '';
  for Change in Changes do
    Text := Text + ExtractFileName(Change.FileName) + ':' + IntToStr(Ord(Change.Kind)) + ' ';
  // A unverändert; B geändert, C gelöscht, D neu.
  Assert.AreEqual(Format('B.pas:%d C.pas:%d D.pas:%d ', [Ord(TFileChangeKind.Changed), Ord(TFileChangeKind.Deleted),
    Ord(TFileChangeKind.Created)]), Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpFreshnessTests);

end.