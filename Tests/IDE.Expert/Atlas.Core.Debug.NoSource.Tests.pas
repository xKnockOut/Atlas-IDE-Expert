unit Atlas.Core.Debug.NoSource.Tests;

// Tests für das Fenster „Kein Quelltext“ (#869): Kopfzeile, Units, Grund, Auswege, Liste ohne Fenster.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasNoSourceTests = class
  public
    /// <summary>Adresse, Modul und Routine aus der Kopfzeile der IDE.</summary>
    [Test]
    procedure ParsesHeader;
    /// <summary>Mögliche Units, die längste zuerst.</summary>
    [Test]
    procedure ListsUnitCandidates;
    /// <summary>Unit, DCU und PAS in den Ordnern.</summary>
    [Test]
    procedure LocatesUnit;
    /// <summary>Grund aus den gesammelten Tatsachen.</summary>
    [Test]
    procedure DecidesReason;
    /// <summary>Auswege je Grund.</summary>
    [Test]
    procedure OffersWays;
    /// <summary>{$D-} und {$DEBUGINFO OFF}, auch in einer Liste.</summary>
    [Test]
    procedure FindsDebugInfoOff;
    /// <summary>Liste der Units ohne Fenster.</summary>
    [Test]
    procedure IgnoresUnits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.NoSource;

function ExistsIn(const AFiles: TArray<string>): TFunc<string, Boolean>;
begin
  Result :=
    function(APath: string): Boolean
    var
      mFile: string;
    begin
      for mFile in AFiles do
      begin
        if SameText(mFile, APath) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

procedure TAtlasNoSourceTests.ParsesHeader;
var
  mPlace: TAtlasNoSourcePlace;
begin
  mPlace := TAtlasNoSourcePlace.Parse(':76f3a2b0 KERNELBASE.RaiseException + 0x62');
  Assert.AreEqual('76F3A2B0', mPlace.Address);
  Assert.AreEqual('KERNELBASE', mPlace.Module);
  Assert.AreEqual('KERNELBASE.RaiseException', mPlace.Routine);
  mPlace := TAtlasNoSourcePlace.Parse('System.SysUtils.FormatFloat(''0.00'',3.5)');
  Assert.AreEqual('', mPlace.Address);
  Assert.AreEqual('', mPlace.Module);
  Assert.AreEqual('System.SysUtils.FormatFloat', mPlace.Routine);
  mPlace := TAtlasNoSourcePlace.Parse(':00405F4C System.@HandleAnyException + $40');
  Assert.AreEqual('System.@HandleAnyException', mPlace.Routine);
end;

procedure TAtlasNoSourceTests.ListsUnitCandidates;
var
  mPlace: TAtlasNoSourcePlace;
begin
  mPlace := TAtlasNoSourcePlace.Parse('Vcl.Forms.TCustomForm.Show');
  Assert.AreEqual('Vcl.Forms.TCustomForm,Vcl.Forms,Vcl', string.Join(',', mPlace.UnitCandidates));
  mPlace := TAtlasNoSourcePlace.Parse('Ohne');
  Assert.AreEqual(Integer(0), Integer(Length(mPlace.UnitCandidates)));
end;

procedure TAtlasNoSourceTests.LocatesUnit;
var
  mFacts: TAtlasNoSourceFacts;
  mExists: TFunc<string, Boolean>;
begin
  mExists := ExistsIn([PathDelim + 'lib' + PathDelim + 'System.SysUtils.dcu',
    PathDelim + 'src' + PathDelim + 'System.SysUtils.pas']);
  mFacts := Default(TAtlasNoSourceFacts);
  TAtlasNoSource.Locate(TAtlasNoSourcePlace.Parse('System.SysUtils.FormatFloat'),
    [PathDelim + 'lib', '', PathDelim + 'src'], mExists, mFacts);
  Assert.AreEqual('System.SysUtils', mFacts.UnitName);
  Assert.AreEqual(PathDelim + 'lib' + PathDelim + 'System.SysUtils.dcu', mFacts.DcuPath);
  Assert.AreEqual(PathDelim + 'src' + PathDelim + 'System.SysUtils.pas', mFacts.PasPath);
  Assert.IsTrue(TAtlasNoSource.IsUnder(mFacts.DcuPath, [PathDelim + 'LIB']));
  Assert.IsFalse(TAtlasNoSource.IsUnder(mFacts.DcuPath, [PathDelim + 'li']));
end;

procedure TAtlasNoSourceTests.DecidesReason;
var
  mFacts: TAtlasNoSourceFacts;
begin
  mFacts := Default(TAtlasNoSourceFacts);
  mFacts.SystemModule := True;
  Assert.AreEqual(Ord(TAtlasNoSourceReason.SystemCode), Ord(TAtlasNoSource.Decide(mFacts)));
  mFacts := Default(TAtlasNoSourceFacts);
  Assert.AreEqual(Ord(TAtlasNoSourceReason.NotInSearchPath), Ord(TAtlasNoSource.Decide(mFacts)), 'nichts gefunden');
  mFacts.DcuPath := 'a.dcu';
  mFacts.LibraryUnit := True;
  Assert.AreEqual(Ord(TAtlasNoSourceReason.DebugDcusOff), Ord(TAtlasNoSource.Decide(mFacts)));
  mFacts.DebugDcus := True;
  Assert.AreEqual(Ord(TAtlasNoSourceReason.DcuOnly), Ord(TAtlasNoSource.Decide(mFacts)));
  mFacts.PasPath := 'a.pas';
  mFacts.DebugInfoOff := True;
  Assert.AreEqual(Ord(TAtlasNoSourceReason.NoDebugInfo), Ord(TAtlasNoSource.Decide(mFacts)));
  mFacts.DebugInfoOff := False;
  Assert.AreEqual(Ord(TAtlasNoSourceReason.NotInSearchPath), Ord(TAtlasNoSource.Decide(mFacts)));
end;

procedure TAtlasNoSourceTests.OffersWays;
var
  mWays: TAtlasNoSourceWays;
begin
  mWays := TAtlasNoSource.Ways(TAtlasNoSourceReason.DebugDcusOff, True, True);
  Assert.IsTrue(TAtlasNoSourceWay.EnableDebugDcus in mWays);
  Assert.IsTrue(TAtlasNoSourceWay.ReturnToOwnCode in mWays);
  Assert.IsTrue(TAtlasNoSourceWay.KeepCpu in mWays);
  Assert.IsFalse(TAtlasNoSourceWay.FindSource in mWays);
  mWays := TAtlasNoSource.Ways(TAtlasNoSourceReason.DebugDcusOff, False, False);
  Assert.IsFalse(TAtlasNoSourceWay.EnableDebugDcus in mWays, 'ohne Konfiguration Debug');
  Assert.IsFalse(TAtlasNoSourceWay.ReturnToOwnCode in mWays, 'ohne eigenen Rahmen');
  mWays := TAtlasNoSource.Ways(TAtlasNoSourceReason.DcuOnly, False, True);
  Assert.IsTrue(TAtlasNoSourceWay.FindSource in mWays);
  mWays := TAtlasNoSource.Ways(TAtlasNoSourceReason.SystemCode, True, True);
  Assert.IsFalse(TAtlasNoSourceWay.FindSource in mWays);
  Assert.IsFalse(TAtlasNoSourceWay.EnableDebugDcus in mWays);
end;

procedure TAtlasNoSourceTests.FindsDebugInfoOff;
begin
  Assert.IsTrue(TAtlasNoSource.DebugInfoOff('unit A;' + sLineBreak + '{$D-}' + sLineBreak + 'interface'));
  Assert.IsTrue(TAtlasNoSource.DebugInfoOff('{$debuginfo off}'));
  Assert.IsTrue(TAtlasNoSource.DebugInfoOff('{$L-,D-}'));
  Assert.IsFalse(TAtlasNoSource.DebugInfoOff('{$D+} // D-'));
  Assert.IsFalse(TAtlasNoSource.DebugInfoOff('{$DEFINE D-}'));
end;

procedure TAtlasNoSourceTests.IgnoresUnits;
var
  mList: string;
begin
  mList := TAtlasNoSource.AddIgnored(' Vcl.Forms ; ', 'System.SysUtils');
  Assert.AreEqual('Vcl.Forms; System.SysUtils', mList);
  Assert.AreEqual(mList, TAtlasNoSource.AddIgnored(mList, 'system.sysutils'), 'schon enthalten');
  Assert.IsTrue(TAtlasNoSource.IsIgnored('VCL.FORMS', 'a,Vcl.Forms'));
  Assert.IsFalse(TAtlasNoSource.IsIgnored('', 'a'));
end;

end.
