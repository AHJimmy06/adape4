"""Focused validation rules at the system boundary."""
import pytest
from backend.models import ErrorAPI
from backend.sistema_validacion import cabin, validate_catalog, seat_codes, allocate_vat


@pytest.mark.parametrize('selection',[[],['1A','1A'],['0A'],['1a'],['A1'],['1AA'],None])
def test_seat_selection_invalid(selection):
    with pytest.raises(ErrorAPI):
        seat_codes(selection)


def test_cabin_capacity_is_derived_and_labels_unique():
    data={'matricula':'at-test','modelo':'Test','capacidad_total':999,'clases':[
        {'codigo':'J','nombre':'Ejecutiva','fila_inicio':1,'filas':2,'columnas':[['A','C'],['D','F']],'capacidad':999},
        {'codigo':'ECO','nombre':'Económica','fila_inicio':3,'filas':2,'columnas':[['A','B'],['C','D']]}]}
    result=validate_catalog('aviones',data)
    assert result['capacidad_total']==16
    assert [c['capacidad'] for c in result['clases']]==[8,8]
    data['clases'][1]['fila_inicio']=2
    with pytest.raises(ErrorAPI):
        validate_catalog('aviones',data)


@pytest.mark.parametrize('field,value',[('iata','AB'),('codigo_pais','ECU'),('latitud',91),('longitud',181),('latitud',True),('zona_horaria','Not/AZone')])
def test_airport_geographic_and_timezone_validation(field,value):
    data=dict(iata='UIO',nombre='Airport',ciudad='Quito',pais='Ecuador',codigo_pais='EC',latitud=0,longitud=0,zona_horaria='America/Guayaquil')
    with pytest.raises(ErrorAPI):
        validate_catalog('aeropuertos',{**data,field:value})


def test_tax_rounding_per_seat_stays_proportional_not_all_remainder_on_last():
    seats=allocate_vat([{'codigo':f'{i}A','subtotal_centavos':51} for i in range(1,101)])
    assert sum(s['iva_centavos'] for s in seats)==765
    assert set(s['iva_centavos'] for s in seats)=={7,8}
