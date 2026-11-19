unit Atlas.Core.Files.Entries.Tests;

// Tests für Objekte je Datei (TAtlasFileEntries).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFileEntriesTests = class
  public
    [Test]
    procedure FindIgnoresCase;
    [Test]
    procedure FindWithoutEntryIsNil;
    [Test]
    procedure DropFreesOwnedEntry;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Files.Entries;

{ TAtlasFileEntriesTests }

procedure TAtlasFileEntriesTests.FindIgnoresCase;
var
  mEntries: TAtlasFileEntries<TStringList>;
  mEntry: TStringList;
begin
  mEntries := TAtlasFileEntries<TStringList>.Create([doOwnsValues]);
  try
    mEntry := TStringList.Create;
    mEntries.Put('C:\Src\Haupt.pas', mEntry);
    Assert.AreSame(mEntry, mEntries.Find('c:\src\HAUPT.pas'));
    Assert.AreEqual('c:\src\haupt.pas', TAtlasFileEntries<TStringList>.Key('C:\Src\Haupt.pas'));
  finally
    mEntries.Free;
  end;
end;

procedure TAtlasFileEntriesTests.FindWithoutEntryIsNil;
var
  mEntries: TAtlasFileEntries<TStringList>;
begin
  mEntries := TAtlasFileEntries<TStringList>.Create([doOwnsValues]);
  try
    Assert.IsNull(mEntries.Find('C:\Src\Fehlt.pas'));
  finally
    mEntries.Free;
  end;
end;

procedure TAtlasFileEntriesTests.DropFreesOwnedEntry;
var
  mEntries: TAtlasFileEntries<TStringList>;
begin
  mEntries := TAtlasFileEntries<TStringList>.Create([doOwnsValues]);
  try
    mEntries.Put('C:\Src\Haupt.pas', TStringList.Create);
    mEntries.Drop('c:\src\haupt.pas');
    Assert.AreEqual(0, Integer(mEntries.Count));
    Assert.IsNull(mEntries.Find('C:\Src\Haupt.pas'));
  finally
    mEntries.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFileEntriesTests);

end.
