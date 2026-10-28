unit Dcc.Eigenschaften;

// #1328, Regel property-accessor-invalid: Fälle, die Atlas meldet, die Delphi
// aber nach den Korpus-Projekten übersetzt.

interface

type
  TArt = (aEins, aZwei);

  TEigenschaften = class
  private
    FX, FY: Integer;
    FWerte: array[TArt] of Integer;
    FName: string;
    procedure SetXY(AIndex: Integer; AWert: Integer);
    procedure SetWert(AIndex: Integer; AWert: Integer);
    function GetFlag(AArt: TArt): Boolean;
    procedure SetFlag(AArt: TArt; const AWert: Boolean);
    function GetText: string; overload;
    function GetText(AArt: TArt): string; overload;
  public
    class function GetVersion: string; virtual;
    // PA1: index mit Feld hinter read (wie F09, mORMot2, SynEdit)
    property X: Integer index 0 read FX write SetXY;
    property Y: Integer index 1 read FY write SetXY;
    // PA2: index mit Array-Element hinter read (SynEdit SynMacroRecorder)
    property Eins: Integer index Ord(aEins) read FWerte[aEins] write SetWert;
    // PA3: index mit Feld hinter read und write (mORMot2 ORM-Klassen)
    property Name: string index 50 read FName write FName;
    // PA4: index mit Aufzählungskonstante, Getter und Setter mit Aufzählungsparameter (mORMot2 mormot.core.log)
    property Flag: Boolean index aZwei read GetFlag write SetFlag;
    // PA5: Klassenmethode (nicht static) als Getter einer Instanz-Property (HtmlViewer UrlConn)
    property Version: string read GetVersion;
    // PA6: überladener Getter, eine Überladung passt (Graphics32 GR32.CPUID)
    property Text: string read GetText;
  end;

implementation

uses
  System.SysUtils;

procedure TEigenschaften.SetXY(AIndex: Integer; AWert: Integer);
begin
  if AIndex = 0 then
    FX := AWert
  else
    FY := AWert;
end;

procedure TEigenschaften.SetWert(AIndex: Integer; AWert: Integer);
begin
  FWerte[TArt(AIndex)] := AWert;
end;

function TEigenschaften.GetFlag(AArt: TArt): Boolean;
begin
  Result := FWerte[AArt] <> 0;
end;

procedure TEigenschaften.SetFlag(AArt: TArt; const AWert: Boolean);
begin
  FWerte[AArt] := Ord(AWert);
end;

function TEigenschaften.GetText: string;
begin
  Result := FName;
end;

function TEigenschaften.GetText(AArt: TArt): string;
begin
  Result := FName + IntToStr(Ord(AArt));
end;

class function TEigenschaften.GetVersion: string;
begin
  Result := '1';
end;

end.
