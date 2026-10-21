unit Atlas.Common.Editing.GitUser.Tests;

// Tests für user.name aus der git-Konfiguration (/todo -o, #297).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGitUserTests = class
  public
    [Test]
    procedure NameInUserSection;
    [Test]
    procedure NameIgnoresOtherSectionsAndComments;
    [Test]
    procedure NameForWalksUp;
    [Test]
    procedure NameForFallsBackToHome;
    [Test]
    procedure NameForWithoutConfig;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.GitUser;

/// <summary>Leser über Paare 'pfad=text'.</summary>
function Reader(const AFiles: TArray<string>): TGitReadFile;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    var
      Pair: string;
    begin
      AText := '';
      for Pair in AFiles do
        if Copy(Pair, 1, Pos('=', Pair) - 1) = AFileName then
        begin
          AText := Copy(Pair, Pos('=', Pair) + 1, MaxInt);
          Exit(True);
        end;
      Result := False;
    end;
end;

procedure TGitUserTests.NameInUserSection;
begin
  Assert.AreEqual('Marco', TGitUser.NameIn('[core]'#10'  bare = false'#10'[user]'#10'  name = Marco'#10));
  Assert.AreEqual('Eva Kollegin', TGitUser.NameIn('[User]'#13#10#9'Name = "Eva Kollegin"'#13#10));
end;

procedure TGitUserTests.NameIgnoresOtherSectionsAndComments;
begin
  Assert.AreEqual('', TGitUser.NameIn('[remote "origin"]'#10'  name = falsch'#10));
  Assert.AreEqual('Marco', TGitUser.NameIn('[user]'#10'; name = alt'#10'  name = Marco # Kommentar'#10));
  Assert.AreEqual('', TGitUser.NameIn(''));
end;

procedure TGitUserTests.NameForWalksUp;
begin
  Assert.AreEqual('Projekt', TGitUser.NameFor('C:\Repo\Src\Sub', 'C:\Users\m',
    Reader(['C:\Repo\.git\config=[user]'#10'name = Projekt', 'C:\Users\m\.gitconfig=[user]'#10'name = Global'])));
  Assert.AreEqual('Projekt', TGitUser.NameFor('/repo/src', '/home/m',
    Reader(['/repo/.git/config=[user]'#10'name = Projekt'])));
end;

procedure TGitUserTests.NameForFallsBackToHome;
begin
  // Repository ohne Namen: die globale Angabe zählt.
  Assert.AreEqual('Global', TGitUser.NameFor('C:\Repo\Src', 'C:\Users\m',
    Reader(['C:\Repo\.git\config=[core]', 'C:\Users\m\.gitconfig=[user]'#10'name = Global'])));
end;

procedure TGitUserTests.NameForWithoutConfig;
begin
  Assert.AreEqual('', TGitUser.NameFor('C:\Repo', '', Reader(nil)));
  Assert.AreEqual('', TGitUser.NameFor('', '', Reader(nil)));
end;

initialization
  TDUnitX.RegisterTestFixture(TGitUserTests);

end.
