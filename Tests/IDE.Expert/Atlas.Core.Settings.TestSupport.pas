unit Atlas.Core.Settings.TestSupport;

// Gemeinsame Hilfen der Einstellungs-Tests (Atlas.Core.Settings.*.Tests).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Contract;

type
  /// <summary>Einstellungsspeicher im Speicher statt in der Registry.</summary>
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  protected
    FValues: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer); virtual;
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

  /// <summary>
  ///   Einstellungsspeicher im Speicher, der wie die Registry alles als Text ablegt: Zahlen lassen sich auch als
  ///   Text lesen und umgekehrt.
  /// </summary>
  TTextStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

implementation

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TTextStore }

constructor TTextStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TTextStore.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

function TTextStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mText: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, mText) then
  begin
    Result := StrToIntDef(mText, ADefault);
  end;
end;

procedure TTextStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TTextStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TTextStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

end.
