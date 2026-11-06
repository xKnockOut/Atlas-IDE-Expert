unit Shell.Composition.DfmPropertyRules.Tests;

// Befehl „Eigenschaftsregeln anwenden“ (#309): fehlende URI, Bereich form, Bereich project ohne Ordner, Auswahl
// nur der Regel dfm-property, keine Befunde für Dateien außer .pas.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Workspaces,
  Shell.Composition.DfmPropertyRules;

type
  [TestFixture]
  TShellDfmPropertyRulesTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FServices: TShellDfmPropertyRulesServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Argumente: Fehler InvalidParams.</summary>
    [Test]
    procedure MissingUriInvalidParams;
    /// <summary>Bereich form: nur die Unit selbst; project ohne Ordner: keine.</summary>
    [Test]
    procedure UnitsByScope;
    /// <summary>Aus allen eingebauten Regeln bleibt nur dfm-property.</summary>
    [Test]
    procedure OnlyDfmPropertyRule;
    /// <summary>Eine Formulardatei selbst hat keine Befunde der Regel.</summary>
    [Test]
    procedure NoFindingsOutsidePas;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Lsp.DfmPropertyRules,
  Atlas.Common.Logging.Providers.Logger;

const
  cUnit = 'C:\Projekt\Haupt.pas';

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

procedure TShellDfmPropertyRulesTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FServices := Default(TShellDfmPropertyRulesServices);
  FServices.Logger := mRegistry.Logger;
  FServices.Workspaces := FRegistry;
  FServices.ReadText := NoText;
end;

procedure TShellDfmPropertyRulesTests.TearDown;
begin
  FServices := Default(TShellDfmPropertyRulesServices);
  FreeAndNil(FRegistry);
end;

procedure TShellDfmPropertyRulesTests.MissingUriInvalidParams;
var
  mArguments: TJSONArray;
  mCode: Integer;
begin
  mArguments := TJSONArray.Create;
  try
    mCode := 0;
    try
      TShellDfmPropertyRules.Apply(FServices, mArguments).Free;
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode);
  finally
    mArguments.Free;
  end;
end;

procedure TShellDfmPropertyRulesTests.UnitsByScope;
var
  mUnits: TArray<string>;
begin
  mUnits := TShellDfmPropertyRules.UnitsFor(FServices, cUnit, TLspDfmPropertyRules.cScopeForm);
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual(cUnit, mUnits[0]);
  mUnits := TShellDfmPropertyRules.UnitsFor(FServices, cUnit, 'project');
  Assert.AreEqual(0, Integer(Length(mUnits)));
end;

procedure TShellDfmPropertyRulesTests.OnlyDfmPropertyRule;
var
  mRules: TArray<IRule>;
begin
  mRules := TShellDfmPropertyRules.RulesWithId(BuiltinRules, TLspDfmPropertyRules.cRuleId);
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual(TLspDfmPropertyRules.cRuleId, mRules[0].Descriptor.Id);
end;

procedure TShellDfmPropertyRulesTests.NoFindingsOutsidePas;
var
  mFindings: TArray<TRuleFinding>;
begin
  Assert.IsFalse(TShellDfmPropertyRules.FindingsFor(FServices, 'C:\Projekt\Haupt.dfm', mFindings));
  Assert.AreEqual(0, Integer(Length(mFindings)));
end;

initialization
  TDUnitX.RegisterTestFixture(TShellDfmPropertyRulesTests);

end.
