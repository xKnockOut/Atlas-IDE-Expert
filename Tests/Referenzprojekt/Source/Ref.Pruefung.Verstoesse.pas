unit Ref.Pruefung.Verstoesse;

// Bewusst eingebaute Regelverstöße. Jede Zeile mit "// ERWARTET: <regel>"
// muss genau diesen Treffer liefern, Zeilen mit "// KEIN-TREFFER: <regel>"
// dürfen ihn nicht liefern. Siehe README.md. Die Verstöße mit FireDAC stehen
// in Ref.Pruefung.Datenbank (nur im optionalen Projekt RefDaten).
//
// Einige Verstöße erzeugen beim Übersetzen gewollt Hinweise oder Warnungen;
// die Liste steht in erwartete-meldungen.txt.
//
// "// ERWARTET-INDEX: <regel>" markiert Treffer von Regeln, die die RTL im
// Index brauchen (z. B. legacy-stack-queue, #1106). Der Golden-Korpus prüft
// je Datei ohne Index; diese Marker prüfen die Tests der Regel mit RTL-Stubs.
// "// ERWARTET-OPTION: <regel>" markiert Treffer von Regeln, die erst mit
// Optionen etwas melden (forbidden-symbol, #1133); die Tests der Regel prüfen
// sie mit der Liste aus README.md.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Contnrs,
  System.Generics.Collections;

type
  TPunkt = record
    X, Y: Integer;
  end;

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET-PROJEKT: unused-public-member
procedure MitWith(var APunkt: TPunkt); // ERWARTET-PROJEKT: unused-public-member
procedure UngenutzteVariable; // ERWARTET-PROJEKT: unused-public-member
procedure Leck; // ERWARTET-PROJEKT: unused-public-member
procedure KeinLeck; // ERWARTET-PROJEKT: unused-public-member
procedure LeererExceptBlock; // ERWARTET-PROJEKT: unused-public-member
procedure Unerreichbar; // ERWARTET-PROJEKT: unused-public-member

implementation

type
  TKnoten = class
  end;

function OhneErgebnis(AWert: Integer): Integer; // ERWARTET: result-not-set
begin
  if AWert > 0 then
    Result := AWert;
end;

procedure MitWith(var APunkt: TPunkt);
begin
  with APunkt do // ERWARTET: with-statement
    X := Y;
end;

procedure UngenutzteVariable;
var
  Unbenutzt: Integer; // ERWARTET: unused-local
  Benutzt: Integer; // KEIN-TREFFER: unused-local
begin
  Benutzt := 1;
  if Benutzt > 0 then
    Exit;
end;

procedure Leck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // ERWARTET: possible-leak
  Liste.Add('x');
end;

procedure KeinLeck;
var
  Liste: TStringList;
begin
  Liste := TStringList.Create; // KEIN-TREFFER: possible-leak
  try
    Liste.Add('x');
  finally
    Liste.Free;
  end;
end;

procedure LeererExceptBlock;
begin
  try
    Abort;
  except end; // ERWARTET: empty-except
end;

procedure Unerreichbar;
begin
  Exit;
  Abort; // ERWARTET: unreachable-code
end;

function RueckwaertsSummieren(const AWerte: TArray<Integer>): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := High(AWerte) to Low(AWerte) do // ERWARTET: for-high-to-low
    Inc(Result, AWerte[I]);
end;

procedure NameUebernehmen(var AName: string);
begin
  AName := AName; // ERWARTET: self-assignment
end;

procedure StapelLesen;
var
  Offen: TObjectStack; // ERWARTET-INDEX: legacy-stack-queue
  Knoten: TKnoten;
begin
  Offen := TObjectStack.Create;
  try
    Offen.Push(TKnoten.Create);
    Knoten := TKnoten(Offen.Pop);
    Knoten.Free;
  finally
    Offen.Free;
  end;
end;

procedure StapelGenerisch;
var
  Fertig: TObjectStack<TKnoten>; // KEIN-TREFFER: legacy-stack-queue
begin
  Fertig := TObjectStack<TKnoten>.Create;
  try
    Fertig.Push(TKnoten.Create);
  finally
    Fertig.Free;
  end;
end;

type
  TBlatt = class(TKnoten)
  public
    Wert: Integer;
  end;

  TAst = class(TKnoten)
  public
    Kinder: Integer;
  end;

procedure Umwandeln(AKnoten: TKnoten; ABlatt: TBlatt);
begin
  TAst(ABlatt).Kinder := 1; // ERWARTET: unrelated-class-cast
  TAst(AKnoten).Kinder := 2; // KEIN-TREFFER: unrelated-class-cast
end;

procedure AltMelden(const AText: string);
begin
end;

procedure Melden(const AText: string);
var
  mAufgabe: TThreadProcedure;
begin
  Writeln(AText); // ERWARTET-OPTION: forbidden-symbol
  Writeln(ErrOutput, AText);
  AltMelden(AText); // ERWARTET-OPTION: forbidden-symbol
  mAufgabe := procedure
    begin
    end;
  TThread.Queue(nil, mAufgabe); // ERWARTET-OPTION: forbidden-symbol
  TThread.Queue(TThread.CurrentThread, mAufgabe);
end;

procedure Aufraeumen(ABlatt: TBlatt; AKnoten: TKnoten);
begin
  TBlatt(ABlatt).Wert := 0; // ERWARTET: redundant-cast
  TBlatt(AKnoten).Wert := 1; // KEIN-TREFFER: redundant-cast
  TObject(ABlatt).Free; // ERWARTET: redundant-cast
end;

procedure Senden(const AText: string; AStrom: TStream);
begin
  AStrom.WriteBuffer(PChar(@AText[1])^, Length(AText) * SizeOf(Char)); // ERWARTET: first-char-address
  AStrom.WriteBuffer(PChar(AText)^, Length(AText) * SizeOf(Char)); // KEIN-TREFFER: first-char-address
end;

procedure Suchen(const AWerte: TArray<Integer>; AWert: Integer; out AGefunden: Boolean);
var
  mWert: Integer;
begin
  AGefunden := False;
  for mWert in AWerte do // ERWARTET: loop-runs-at-most-once
  begin
    if mWert = AWert then
      AGefunden := True;
    Exit;
  end;
  for mWert in AWerte do // KEIN-TREFFER: loop-runs-at-most-once
    if mWert = AWert then
    begin
      AGefunden := True;
      Exit;
    end;
end;

function Beschriften(const AName: string; AAnzahl: Integer): string;
begin
  Result := Format('%d Einträge für %s', [AName, AAnzahl]); // ERWARTET: format-args
  Result := Format('%s: %d Einträge', [AName, AAnzahl]); // KEIN-TREFFER: format-args
end;

type
  TGeraet = class
  protected
    procedure Starten(AStufe: Integer); virtual;
    procedure Stoppen; virtual;
  end;

  TDrucker = class(TGeraet)
  protected
    procedure Starten(AStufe: Integer); override;
    procedure Stoppen; override;
  public
    procedure Vorbereiten;
  end;

procedure TGeraet.Starten(AStufe: Integer);
begin
end;

procedure TGeraet.Stoppen;
begin
end;

procedure TDrucker.Starten(AStufe: Integer); // ERWARTET: override-only-inherited
begin
  inherited Starten(AStufe);
end;

procedure TDrucker.Stoppen; // KEIN-TREFFER: override-only-inherited
begin
  inherited;
  Vorbereiten;
end;

procedure TDrucker.Vorbereiten;
begin
  inherited; // ERWARTET: inherited-without-ancestor
  Stoppen;
end;

end.
