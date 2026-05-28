create or replace package body  xxsvb_kvi_py_betverzoeknp_1_1_tmp_dev as

  -- Package voor Laden PAY betaalverzoek als loonelementen.

  -- Modification History
  --
  -- Author        Date        Version   Description
  -- ------------- ----------- --------- ---------------------------------------
  -- AVJVDORE      03-APR-2017 1.0       Initial creation
  -- AVJVDORE      19-OCT-2017 2.0       Synchronized with koppelvlakkendocument 1.0
  -- avjvdore      31-okt-2017 2.1       Added use of function get_zok_ass_id
  -- avflidua      14-dec-2017 2.2       to_rcvd_table: add extra param error_code, error_text
  --                                     process_betaalverzoek: change the exception handling
  -- AVJVDORE      22.12.2017  2.3       Some debugging for INT1
  -- AVRJDORE      11.01.2017  2.4       periode uitgevuld tot 2 decimalen bij het bepalen van de effective date
  -- AVJVDORE      15.01.2018  2.5       process_betaalverzoek: parameter xd_verwachte_betaaldatum toegevoegd
  -- AVJVDORE      01.03.2018  2.6       added use of get_pay_date
  -- AVJVDORE      02.03.2018  2.7       added use of get_alternate_element_type_id
  -- avjvdore      19.03.2019  2.8       PGBF-1370 process_betaalverzoek(): ps_start_datum in call naar xxsvb_generic_int.write_service_status
  -- avjvdore      19.03.2019  2.9       PGBF-1369 aantal functiecalls omgekat van xxsvb_generic naar pgb package
  -- avjvdore      04.04.2019  2.10      PGBF-1425 removed revision()
  -- avjvdore      12.04.2019  2.11      PGBF-1292 added cP_retry_service_request
  -- avjvdore      24.04.2019  2.12      PGBF-1293: cp_retry_service_request(): gebruik van xxsvb_generic_int.check_service_message% functies
  -- avjvdore      01.05.2019  2.13      PGBF-1181: implemented declaratienummer_exists() en get_decl_rcvd_date()
  -- avjvdore      10.05.2019  2.14      PD-44: implemented clean_data()
  -- avjvdore      06.08.2019  2.15      PD-140: to_rcvd_table: vastlegging van het veld correctieop
  -- avjvdore      11.02.2020  2.16      PD-2109 added healthcheck(), removed ISG references
  -- avjvdore      06.07.2020  2.17      process_betaalverzoek(): exception handler unexpected_error, call naar write_service_status toegevoegd.
  -- avjvdore      21.07.2020  2.18      process_betaalverzoek(): verkeerde volgorde van raise_exception en write service status gefixt
  -- avjvdore      03.08.2021  2.19      PF-855 + van correctieop_type  ( XXSVB_KVI_PY_BETVERZOEKNP_1_1 )
  -- avjvdore      13.08.2021  3.0       PF-795 process_betaalverzoek: implementie van svj datum naar niewe iv 'SVJ datum) (voor Maandloon, Gewerkte uren en Feestdagenuitkering)
  -- avjvdore      23.12.2021  3.1       PF-1032 implementatie van profieloptie XXSVB_PAY_PROCESS_SVJ
  -- avjvdore      07.01.2022  3.2       PF-1040 process_betaalverzoek(): Afleiden van SVJ moet op basis van actieve verloningsperiode ipv systeem datum
  -- avjvdore      14.09.2022  3.3       PF-1204 process_betaalverzoek(): Zetten van lr_ee.attribute4 met zorgovereenkomstnummer voor call naar xxsvb_hr_api.call_create_ee_api
  -- avjvdore      05.01.2023  3.4       PF-1277 declaratienummer_exists(): nvl verwijderd om attribute1 om index gebruik mogelijk te maken
  -- avjvdore      02.03.2023  3.5       PF-1308 process_betaalverzoek(): call naar fnd_msg_pub.initialize toegevoegd
  -- avjvdore      23.11.2023  3.6       PF-1444 process_betaalverzoek(): andere methode van parkeren SVJs
  -- avjvdore      23.11.2023  3.7       PF-1445 process_betaalverzoek(): geen SVJ datum voor component EENMALIGE_UITKERING_OVERLIJDEN_BGH
  -- avjvdore      06.01.2025  3.8       PF-3149 process_betaalverzoek(): declaraties over eerdere periodes landen onterecht als SVJ in december 2024
  -- avjvdore      16.01.2025  3.9       PF-3215 * process_betaalverzoek(): Opting out SVJ liepen in error bij XXSVB_PAY_PROCESS_SVJ=N omdat effective date niet werd gezet
  --                                             * cp_retry_service_request(): call naar oude versie van package (xxsvb_kvi_py_betverzoeknp_1_0) aangepast naar huidige versie ( xxsvb_kvi_py_betverzoeknp_1_1 )
  -- ZFuad         11-07-2025  3.10      EB-1945 SVJ in/uitparkeren aanpassen op RDAH
  -- avjvdore      01-09-2025  4.0       PF-3834: Aanpassingen tbv herinrichting Finance
  -- avjvdore      07-10-2025  4.1       PF-3834: Reserve3 krijgt waarde INCOMPLETE om te voorkomen dat de journaalregel wordt goedgekeurd
  --                                              door "GL Import" zonder dat het custom post-transfer to GL proces heeft gedraaid.
  -- avjvdore      12.12.2025  4.2       PF-4682: process_betaalverzoek(): costing van budgethouder en zorgverlener (beiden voortaan vanuit assignment) en defaulted wet en verstrekker niet langer vanuit koppelvlak
  -- AVOPOHLE      28-MAY-2026 4.3       from_rcvd_table(): nieuwe kolommen zorgwet, verstrekker, budget_gebruikt, algemene_middelen_bedrag,
  --                                       type_algemene_middelen, funding_y_n, bijstorting_bedrag, ind_wglstn_budget_comp,
  --                                       ind_wglstn_algeme_middel_comp toegevoegd tbv retry functionaliteit.
  --                                     from_rcvd_table(): bugfix correctieop_type werd gevuld met correctieop ipv correctieop_type.
  --                                     clean_data(): nieuwe varchar2 velden zorgwet, verstrekker, type_algemene_middelen, funding_y_n toegevoegd.


  -- Package name used in calls to message utilities:
  gcc_package_name constant varchar2(255) := 'xxsvb_kvi_py_betverzoeknp_1_1';
  gcc_service_name constant varchar2(255) := 'betaalverzoekNatuurlijkPersoon';

  -- API return status:
  -- gcc_ret_sts_success = the API was successful in performing all the operations requested by its caller.
  gcc_ret_sts_success constant varchar2(1) := fnd_api.g_ret_sts_success;
  -- gcc_ret_sts_error = the API failed to perform one or more of the operations requested by its caller.
  gcc_ret_sts_error constant varchar2(1) := fnd_api.g_ret_sts_error;
  -- gcc_ret_sts_unexp_error = the API was not able to perform any operation because of an unexpected error.
  gcc_ret_sts_unexp_error constant varchar2(1) := fnd_api.g_ret_sts_unexp_error;

  -- Error severities for exception handling:
  -- Severity for recoverable errors.
  gnc_error constant pls_integer := 1;
  -- Severity for unexpected errors.
  gnc_unexpected constant pls_integer := 2;

  -- Private constant declarations
  gcc_verloningskalender constant varchar2(50) := 'Verloningskalender';

  -- Private variable declarations

  -- Private program units -----------------------------------------------------------

  /**
  * Procedure log: Logging voor APEX
  */
  procedure log(p_text varchar2) is
  begin
    null;
    apex_debug.message(gcc_package_name || '.' || p_text);
  end log;


  -- Public program units --------------------------------------------------------------

  procedure to_rcvd_table
  (
    pc_message_id    in varchar2
   ,pr_betaalverzoek in grt_pay_betaalverzoek
   ,xc_return_status in out nocopy varchar2
   ,xc_error_code    out nocopy varchar2
   ,xc_error_text    out nocopy varchar2
   ,xc_message       out nocopy varchar2
  ) is
    lcc_unit         varchar2(30) := 'to_rcvd_table';
    lc_return_status varchar2(1);

    lr_bv_hdr  xxsvb.xxsvb_betaalverzoek_np_rcvd%rowtype;
    lr_bv_rgls xxsvb.xxsvb_betaalverz_np_rgls_rcvd%rowtype;
    lr_bv_dtls xxsvb.xxsvb_betaalverz_np_dtls_rcvd%rowtype;

    i number;
    j number;

    pragma autonomous_transaction;
  begin

    lc_return_status := nvl(xc_return_status, gcc_ret_sts_success);
    if lc_return_status = gcc_ret_sts_unexp_error
    then
      return;
    end if;

    lr_bv_hdr.message_id                    := pc_message_id;
    lr_bv_hdr.received_date                 := systimestamp;
    lr_bv_hdr.declaratienummer              := pr_betaalverzoek.declaratienummer;
    lr_bv_hdr.declper_jaar                  := pr_betaalverzoek.declaratieperiode.declaratiejaar;
    lr_bv_hdr.declper_maand                 := pr_betaalverzoek.declaratieperiode.declaratiemaand;
    lr_bv_hdr.zorgovereenkomstnummer        := pr_betaalverzoek.zorgovereenkomstnummer;
    lr_bv_hdr.totaalbedrag                  := pr_betaalverzoek.totaalbedrag;
    lr_bv_hdr.aantaluren                    := pr_betaalverzoek.aantaluren;
    lr_bv_hdr.inclusiefvakantieuren         := pr_betaalverzoek.inclusiefvakantieuren;
    lr_bv_hdr.correctieop                   := pr_betaalverzoek.correctieop;
    lr_bv_hdr.correctieop_type              := pr_betaalverzoek.correctieop_type;
    lr_bv_hdr.zorgwet                       := pr_betaalverzoek.zorgwet;
    lr_bv_hdr.verstrekker                   := pr_betaalverzoek.verstrekker;
    lr_bv_hdr.budget_gebruikt               := pr_betaalverzoek.budget_gebruikt;
    lr_bv_hdr.algemene_middelen_bedrag      := pr_betaalverzoek.algemene_middelen_bedrag;
    lr_bv_hdr.type_algemene_middelen        := pr_betaalverzoek.type_algemene_middelen;
    lr_bv_hdr.funding_y_n                   := pr_betaalverzoek.funding_y_n;
    lr_bv_hdr.bijstorting_bedrag            := pr_betaalverzoek.bijstorting_bedrag;
    lr_bv_hdr.ind_wglstn_budget_comp        := pr_betaalverzoek.ind_wglstn_budget_comp;
    lr_bv_hdr.ind_wglstn_algeme_middel_comp := pr_betaalverzoek.ind_wglstn_algeme_middel_comp;

    begin
      insert into xxsvb.xxsvb_betaalverzoek_np_rcvd
      values lr_bv_hdr;
    exception
      when dup_val_on_index then
        xxsvb_utl_custom_messaging.unique_constraint_violated(pc_column_name => 'MESSAGE_ID', pc_column_value => pc_message_id);
        raise xxsvb_globals.ge_unexpected_error;
    end;

    i := pr_betaalverzoek.declaratieregels.first;

    while i is not null
    loop

      lr_bv_rgls.message_id            := pc_message_id;
      lr_bv_rgls.regelnummer           := pr_betaalverzoek.declaratieregels(i).regelnummer;
      lr_bv_rgls.component             := pr_betaalverzoek.declaratieregels(i).component;
      lr_bv_rgls.bedrag                := pr_betaalverzoek.declaratieregels(i).bedrag;


      begin

        insert into xxsvb.xxsvb_betaalverz_np_rgls_rcvd
        values lr_bv_rgls;

      exception
        when dup_val_on_index then
          xxsvb_utl_custom_messaging.unique_constraint_violated(pc_column_name  => 'MESSAGE_ID/REGELNUMMER'
                                                               ,pc_column_value => pc_message_id || '/' || lr_bv_rgls.regelnummer);
          raise xxsvb_globals.ge_unexpected_error;
      end;

      j := pr_betaalverzoek.declaratieregels(i).details.first;

      while j is not null
      loop
        lr_bv_dtls.message_id  := pc_message_id;
        lr_bv_dtls.regelnummer := lr_bv_rgls.regelnummer;
        lr_bv_dtls.volgnummer  := j;
        lr_bv_dtls.aantal      := pr_betaalverzoek.declaratieregels(i).details(j).aantal;
        lr_bv_dtls.eenheid     := pr_betaalverzoek.declaratieregels(i).details(j).eenheid;

        begin

          insert into xxsvb.xxsvb_betaalverz_np_dtls_rcvd
          values lr_bv_dtls;

        exception
          when dup_val_on_index then
            xxsvb_utl_custom_messaging.unique_constraint_violated(pc_column_name  => 'MESSAGE_ID/REGELNUMMER/DETAILVOLGNUMMER'
                                                                 ,pc_column_value => pc_message_id || '/' || lr_bv_dtls.regelnummer || '/' ||
                                                                                     lr_bv_dtls.volgnummer);

            raise xxsvb_globals.ge_unexpected_error;
        end;

        j := pr_betaalverzoek.declaratieregels(i).details.next(j);

      end loop;

      i := pr_betaalverzoek.declaratieregels.next(i);

    end loop;
    commit;

    xc_return_status := lc_return_status;
  exception
    when xxsvb_globals.ge_error then
      rollback;
      xxsvb_utl_exceptions.raise_error(gnc_error, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xc_return_status := gcc_ret_sts_error;
    when xxsvb_globals.ge_unexpected_error then
      rollback;
      xxsvb_utl_exceptions.raise_error(gnc_unexpected, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xc_return_status := gcc_ret_sts_unexp_error;
    when xxsvb_globals.ge_fatal then
      rollback;
      raise;
    when others then
      rollback;
      if sqlcode = -20030
      then
        raise xxsvb_globals.ge_fatal;
      end if;
      xxsvb_utl_custom_messaging.oracle_error(sqlerrm, lcc_unit, gcc_package_name);
      xxsvb_utl_exceptions.raise_error(gnc_unexpected, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xc_return_status := gcc_ret_sts_unexp_error;

  end to_rcvd_table;

  function from_rcvd_table
  (
    pc_message_id    in varchar2
   ,xc_return_status in out nocopy varchar2
   ,xc_message       out nocopy varchar2
  ) return grt_pay_betaalverzoek is

    lr_retval grt_pay_betaalverzoek;
    lr_bv_hdr xxsvb.xxsvb_betaalverzoek_np_rcvd%rowtype;

    i number := 0;
    j number := 0;

  begin

    select *
      into lr_bv_hdr
      from xxsvb.xxsvb_betaalverzoek_np_rcvd
     where message_id = pc_message_id;

    lr_retval.declaratienummer                  := lr_bv_hdr.declaratienummer;
    lr_retval.declaratieperiode.declaratiejaar  := lr_bv_hdr.declper_jaar;
    lr_retval.declaratieperiode.declaratiemaand := lr_bv_hdr.declper_maand;
    lr_retval.zorgovereenkomstnummer            := lr_bv_hdr.zorgovereenkomstnummer;
    lr_retval.aantaluren                        := lr_bv_hdr.aantaluren;
    lr_retval.totaalbedrag                      := lr_bv_hdr.totaalbedrag;
    lr_retval.inclusiefvakantieuren             := lr_bv_hdr.inclusiefvakantieuren;
    lr_retval.correctieop                       := lr_bv_hdr.correctieop;
    lr_retval.correctieop_type                  := lr_bv_hdr.correctieop_type;  -- 4.3 bugfix: was lr_bv_hdr.correctieop
    lr_retval.zorgwet                           := lr_bv_hdr.zorgwet;           -- 4.3
    lr_retval.verstrekker                       := lr_bv_hdr.verstrekker;       -- 4.3
    lr_retval.budget_gebruikt                   := lr_bv_hdr.budget_gebruikt;   -- 4.3
    lr_retval.algemene_middelen_bedrag          := lr_bv_hdr.algemene_middelen_bedrag;   -- 4.3
    lr_retval.type_algemene_middelen            := lr_bv_hdr.type_algemene_middelen;     -- 4.3
    lr_retval.funding_y_n                       := lr_bv_hdr.funding_y_n;               -- 4.3
    lr_retval.bijstorting_bedrag                := lr_bv_hdr.bijstorting_bedrag;         -- 4.3
    lr_retval.ind_wglstn_budget_comp            := lr_bv_hdr.ind_wglstn_budget_comp;    -- 4.3
    lr_retval.ind_wglstn_algeme_middel_comp     := lr_bv_hdr.ind_wglstn_algeme_middel_comp; -- 4.3

    for r in (select *
                from xxsvb.xxsvb_betaalverz_np_rgls_rcvd
               where message_id = pc_message_id)
    loop

      i := i + 1;

      lr_retval.declaratieregels(i).regelnummer := r.regelnummer;
      lr_retval.declaratieregels(i).component := r.component;
      lr_retval.declaratieregels(i).bedrag := r.bedrag;

      for d in (select *
                  from xxsvb.xxsvb_betaalverz_np_dtls_rcvd
                 where message_id = pc_message_id
                   and regelnummer = r.regelnummer
                 order by volgnummer)
      loop

        j := j + 1;

        lr_retval.declaratieregels(i).details(j).aantal := d.aantal;
        lr_retval.declaratieregels(i).details(j).eenheid := d.eenheid;

      end loop;

    end loop;

    return lr_retval;

  exception
    when no_data_found then
      xc_return_status := gcc_ret_sts_error;
      xc_message       := 'Onbekend message id: ' || pc_message_id;

  end from_rcvd_table;

 function clean_data
  (
    pr_betaalverzoek in grt_pay_betaalverzoek
  )
  return grt_pay_betaalverzoek
  is
    lr_retval grt_pay_betaalverzoek;
    i         number;
    j         number;
  begin

    -- initialize all fields in lr_retval
    lr_retval := pr_betaalverzoek;


    -- now 'fix' all varchar2 fields
    lr_retval.declaratienummer          := xxsvb_generic_int.strip(pr_betaalverzoek.declaratienummer);
    lr_retval.correctieop               := xxsvb_generic_int.strip(pr_betaalverzoek.correctieop);
    lr_retval.zorgovereenkomstnummer    := xxsvb_generic_int.strip(pr_betaalverzoek.zorgovereenkomstnummer);
    lr_retval.inclusiefvakantieuren     := xxsvb_generic_int.strip(pr_betaalverzoek.inclusiefvakantieuren);
    lr_retval.zorgwet                   := xxsvb_generic_int.strip(pr_betaalverzoek.zorgwet);                -- 4.3
    lr_retval.verstrekker               := xxsvb_generic_int.strip(pr_betaalverzoek.verstrekker);            -- 4.3
    lr_retval.type_algemene_middelen    := xxsvb_generic_int.strip(pr_betaalverzoek.type_algemene_middelen); -- 4.3
    lr_retval.funding_y_n               := xxsvb_generic_int.strip(pr_betaalverzoek.funding_y_n);            -- 4.3

    i := pr_betaalverzoek.declaratieregels.first;

    while i is not null
    loop

      lr_retval.declaratieregels(i).regelnummer  := xxsvb_generic_int.strip(pr_betaalverzoek.declaratieregels(i).regelnummer);
      lr_retval.declaratieregels(i).component    := xxsvb_generic_int.strip(pr_betaalverzoek.declaratieregels(i).component);

      j := pr_betaalverzoek.declaratieregels(i).details.first;

      while j is not null
      loop

        lr_retval.declaratieregels(i).details(j).eenheid := xxsvb_generic_int.strip(pr_betaalverzoek.declaratieregels(i).details(j).eenheid);
        j := pr_betaalverzoek.declaratieregels(i).details.next(j);

      end loop;

      i := pr_betaalverzoek.declaratieregels.next(i);

    end loop;

    return lr_retval;

  end clean_data;

  function get_pay_date
  (
    pc_payroll_name varchar2
  , pd_date date
  ) return date result_cache
  is
    l_retval date;
  begin

    select tp.pay_advice_date
      into l_retval
      from pay_payrolls_f py
           , per_time_periods tp
      where tp.payroll_id = py.payroll_id
        and py.payroll_name = pc_payroll_name
        and pd_date between tp.start_date and tp.end_date
        and pd_date between py.effective_start_date and py.effective_end_date   ;

    return l_retval;

  exception
  when no_data_found
    then return null;

  end get_pay_date;



  procedure get_alternate_element_type_id
  (
    pc_component in varchar2
  , xn_element_type_id out number
  , xc_reden out varchar2
  )
  is
  begin

    select etei.element_type_id, etei.eei_information2
      into xn_element_type_id, xc_reden
      from pay_element_type_extra_info etei
      where etei.information_type = 'XX_SVB_SERVICE_MAPPING'
        and etei.eei_information_category = 'XX_SVB_SERVICE_MAPPING'
        and etei.eei_information1 = pc_component;

  exception
    when no_data_found
    then
      xn_element_type_id := -1;

  end get_alternate_element_type_id ;


  function get_decl_rcvd_date
  (
    pc_declaratienummer varchar2
  ) return date
  is
    ld_retval date;
  begin

    select cast(rc.received_date as date)
      into ld_retval
      from xxsvb.xxsvb_betaalverzoek_np_rcvd rc
           ,xxsvb.xxsvb_service_statuses ss
      where rc.message_id = ss.message_id
        and rc.declaratienummer = pc_declaratienummer
         and ss.return_status = gcc_ret_sts_success;

    return ld_retval;

  exception
  when no_data_found
    then
      select max(creation_date)
        into ld_retval
        from pay_element_entries_f
        where nvl(attribute1,'!@%$*&^') = pc_declaratienummer;

      return ld_retval;

  end get_decl_rcvd_date;

  function et_id
  (
    p_ele_name varchar2
  )
  return number
  is
    l_et_id number;

  begin
    select distinct et.element_type_id
      into l_et_id
      from pay_element_types_f et
      where et.element_name = p_ele_name;

    return l_et_id;

  end et_id;




  function svj_eff_date
  (
    pn_ass_id number
  , pn_et_id number
  , pd_svj_datum date
  , pn_iv_id_svj_datum number
  )
  return date
  is

    ld_retval date;

    ld_huidige_periode date := xxsvb_pay_process.last_closed_payroll_period + 1;

  begin

    --Bepaal svj entry voor de svj datum/component periode binnen het huidige jaar
    select max(ee.effective_start_date)
      into ld_retval
      from pay_element_entries_f ee
           , pay_element_entry_values_f eev
      where ee.element_entry_id = eev.element_entry_id
        and ee.assignment_id = pn_ass_id
        and ee.element_type_id = pn_et_id
        and trunc( ee.effective_start_date , 'YYYY' ) = trunc( ld_huidige_periode, 'YYYY' ) -- kijk alleen naar het huidige jaar
        and ee.effective_start_date between eev.effective_start_date and eev.effective_end_date
        and eev.input_value_id = pn_iv_id_svj_datum
        and eev.screen_entry_value = fnd_date.date_to_canonical( pd_svj_datum )
    ;

     -- als er nog geen svj is voor deze component in het huidige jaar dan moet de entry landen in de huidige periode
    return nvl( ld_retval, trunc(ld_huidige_periode,'MM') ) ;

  end svj_eff_date;


  function declaratienummer_exists
  (
    pc_declaratienummer varchar2
  )
  return boolean
  is
    ln_cnt number;
  begin

    select count(1)
      into ln_cnt
      from pay_element_entries_f
      where attribute1 = pc_declaratienummer;

    if ln_cnt > 0
    then
      return true;
    else
      return false;
    end if;

  end declaratienummer_exists;

  /**
  * Procedure process_betaalverzoek: Laden PAY betaalverzoek als loonelementen.
  *
  */

  procedure process_betaalverzoek
  (
    pc_message_id    in varchar2
   ,pr_betaalverzoek in grt_pay_betaalverzoek
   ,xd_verwachte_betaaldatum out nocopy date
   ,xc_return_status in out nocopy varchar2
   ,xc_error_code    out nocopy varchar2
   ,xc_error_text    out nocopy varchar2
   ,xc_message       out nocopy varchar2
  ) is
    lcc_unit constant varchar2(30) := 'process_betaalverzoek';
    lc_return_status varchar2(1);
    lc_error_code    varchar2(30);
    lc_error_text    varchar2(2000);
    lc_message       varchar2(4000);

    ge_warning exception;
    pragma exception_init(ge_warning, -20005);

    ln_payroll_id              number := xxsvb_hr_api.get_payroll_id();
    lr_ee                      xxsvb_hr_api.grt_ee_api;
    lr_ee_null                 xxsvb_hr_api.grt_ee_api;
    ln_ass_id                  number;
    lc_budgethoudernummer      varchar2(15);
    lc_zorgverlenernummer      varchar2(15);
    ln_element_type_id         number;
    ln_element_link_id         number;
    lc_el_costable_type        varchar2(30);
    ld_date_earned             date;

    ln_iv_id_gewerkte_uren     number;
    ln_iv_id_totaalbedrag      number;
    ln_iv_id_salaris           number;
    ln_iv_id_incl_vakantieuren number;
    ln_iv_id_aantal_uren       number;
    ln_iv_id_bedrag            number;
    ln_iv_id_svj_datum         number;

    ln_iv_id_reden             number;
    ls_start_timestamp         timestamp;
    ld_prv_rcvd_date           date;
    ld_svj_datum               date;
    lc_profile_process_svj     varchar2(1) := fnd_profile.value('XXSVB_PAY_PROCESS_SVJ');
    lc_zok_sv_type             varchar2(50);
    lc_soortovereenkomst       varchar2(200);
    ld_huidige_periode date := xxsvb_pay_process.last_closed_payroll_period + 1;

    lr_betaalverzoek  grt_pay_betaalverzoek;


    i     number;
    j     number := 0;
    d     number;
    l_cnt number := 0;
    lc_reden varchar2(100);

  begin

    fnd_msg_pub.initialize; -- 3.5

    lc_return_status := nvl(xc_return_status, gcc_ret_sts_success);
    --

    log(lcc_unit || ': Start....');
    log(lcc_unit || ': Profile option XXSVB_PAY_PROCESS_SVJ=' || lc_profile_process_svj);

    fnd_global.apps_initialize
    (
      user_id      => 1150  --AVFUSE
    , resp_id      => 50777 --PGB
    , resp_appl_id => 800   --Human Resources
    );

    lr_betaalverzoek := clean_data( pr_betaalverzoek );

    -- sla ontvangen message data op
    to_rcvd_table(pc_message_id    => pc_message_id
                 ,pr_betaalverzoek => lr_betaalverzoek
                 ,xc_return_status => lc_return_status
                 ,xc_error_code    => lc_error_code
                 ,xc_error_text    => lc_error_text
                 ,xc_message       => lc_message);

    if lc_return_status = gcc_ret_sts_success
    then

      -- bepaal assignment_id obv zoknummer
      -- plus budgethoudernummer en zorgverlenernummer tbv costingsleutel
      ln_ass_id             := pgb.zoknr_ass_id( lr_betaalverzoek.zorgovereenkomstnummer );
      lc_budgethoudernummer := pgb.zvl_buh_nr( ln_ass_id );
      lc_zorgverlenernummer := substr( pgb.zvl_nr( ln_ass_id ), instr(pgb.zvl_nr( ln_ass_id ),'N') , 9 );



      if ln_ass_id is null
      then
        xxsvb_utl_custom_messaging.data_not_found(pc_entity_name     => 'Zorgovereenkomst'
                                                 ,pc_column_name     => 'Zorgovereenkomstnummer'
                                                 ,pc_value_not_found => lr_betaalverzoek.zorgovereenkomstnummer);
        raise xxsvb_globals.ge_unexpected_error;
      end if;


      -- check if declaratienummer already exists
      if declaratienummer_exists( lr_betaalverzoek.declaratienummer )
      then
        ld_prv_rcvd_date := get_decl_rcvd_date( lr_betaalverzoek.declaratienummer );
        xxsvb_utl_custom_messaging.set_message('DPGB-F1005');
        xxsvb_utl_custom_messaging.set_token('DECLARATIENUMMER', lr_betaalverzoek.declaratienummer);
        xxsvb_utl_custom_messaging.set_token('VERWERKINGSDATUM', to_char(ld_prv_rcvd_date, 'fmdd month YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=DUTCH') ) ;
        raise xxsvb_globals.ge_unexpected_error;
      end if;

      -- als de declaratiegegevens gevuld zijn, bepalen we de date-earned obv aangeleverde declaratieperiode
      -- else de date earned wordt geacht de last day vn vorige maand te zijn.
      if lr_betaalverzoek.declaratieperiode.declaratiemaand is not null
      then

        ld_date_earned := last_day(to_date('01' || lpad(lr_betaalverzoek.declaratieperiode.declaratiemaand,2,'0') ||
                                           lr_betaalverzoek.declaratieperiode.declaratiejaar
                                          ,'DDMMYYYY'));

      else

        ld_date_earned := last_day(add_months(sysdate, -1));

      end if;

      -- bepaal sv_type en soort overeenkomst op basis van datum huidige periode
      -- dat wordt eenmalig bepaald voor inparkeren van SVJ
      lc_zok_sv_type := pgb.zok_type_sv ( ln_ass_id , ld_huidige_periode );
      lc_soortovereenkomst := pgb.zok_overeenkomst(ln_ass_id ,ld_huidige_periode );

      i := lr_betaalverzoek.declaratieregels.first();
      while i is not null
      loop

        lr_ee        := lr_ee_null;
        lc_reden     := null;
        ld_svj_datum := null;

        log(lcc_unit || ': Component=' || lr_betaalverzoek.declaratieregels(i).component);

        -- 1st try to map to element type id
        ln_element_type_id := xxsvb_hr_api.get_element_type_id(lr_betaalverzoek.declaratieregels(i).component);

        if ln_element_type_id < 0
        then

          --2nd try to map to element type id
          get_alternate_element_type_id(lr_betaalverzoek.declaratieregels(i).component,ln_element_type_id,lc_reden);

          if ln_element_type_id < 0
          then

            xxsvb_utl_custom_messaging.data_not_found(pc_entity_name     => 'Component'
                                                     ,pc_column_name     => 'Component naam'
                                                     ,pc_value_not_found => lr_betaalverzoek.declaratieregels(i).component);
            raise xxsvb_globals.ge_unexpected_error;
          end if;
        end if;

        ln_iv_id_aantal_uren       := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Aantal uren');
        ln_iv_id_gewerkte_uren     := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Gewerkte uren');
        ln_iv_id_incl_vakantieuren := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Inclusief vakantieuren');
        ln_iv_id_salaris           := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Salaris');
        ln_iv_id_totaalbedrag      := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Totaalbedrag');
        ln_iv_id_bedrag            := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Bedrag');
        ln_iv_id_reden             := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'Reden');
        ln_iv_id_svj_datum         := xxsvb_hr_api.get_input_value_id(ln_element_type_id, 'SVJ datum');


        -- check of het een salaris vorig jaar (SVJ) betreft ( AVJ's landen wel in de opgegeven periode )


        if  ( lr_betaalverzoek.declaratieregels(i).component not like '%AVJ' )
           and
           ( lr_betaalverzoek.declaratieregels(i).component <> 'EENMALIGE_UITKERING_OVERLIJDEN_BGH' ) -- 3.7
        then
          if (
                  ( nvl(lc_profile_process_svj,'Y') <> 'N' )
                   and
                  ( trunc( ld_date_earned, 'YYYY' ) < trunc( ld_huidige_periode , 'YYYY' ) )
                )
          then

            ld_svj_datum := ld_date_earned;
            lr_ee.effective_date :=  svj_eff_date( ln_ass_id, ln_element_type_id, ld_date_earned, ln_iv_id_svj_datum );
            ld_date_earned := last_day(lr_ee.effective_date);

          elsif
             (
               ( lc_profile_process_svj = 'N' )
               and
               ( trunc( ld_date_earned, 'YYYY' ) < trunc( sysdate, 'YYYY' ) ) -- LET OP VERSCHIL MET BOVENSTAANDE IF-tak. Hier wordt gebruik gemaakt van SYSDATE ipv ld_huidige_periode
             )
          then

            ld_svj_datum := ld_date_earned;      -- zet svj datum om verderop te kunnen inparkeren in geval van OIN/ALL

            -- zet lr_ee.effective_date en ld_date_earned voor OOUT entry
            lr_ee.effective_date := greatest( trunc( sysdate, 'YYYY' ), pgb.zvl_hire_date(ln_ass_id));
            ld_date_earned := last_day(lr_ee.effective_date);

          else  -- declaratieperiode valt sowieso in het jaar van de huidige verloningsperiode

            lr_ee.effective_date       := ld_date_earned;

          end if;

        else

          lr_ee.effective_date       := ld_date_earned;

        end if;

        -- INPARKEREN SVJ
        -- ( Verwerk SVJ niet indien profieloptie op N staat en het een zok betreft met OIN of ALL of soortovereenkomst AO is )
        if (
             ( nvl( lc_profile_process_svj, 'Y' ) = 'N' )
             and
             ( ld_svj_datum is not null )
             and
             ( lc_zok_sv_type in ( 'OIN', 'ALL' )
              or  lc_soortovereenkomst = 'AO'
             )
           )
        then
          xxsvb_utl_custom_messaging.set_message('DPGB-F0005');
          raise ge_warning;
        end if;

        ln_element_link_id := xxsvb_hr_api.get_element_link_id(ln_payroll_id, ln_element_type_id);

        select costable_type
          into lc_el_costable_type
          from pay_element_links_f el
          where el.element_link_id = ln_element_link_id;

        log(lcc_unit || ': ln_element_type_id  =' || ln_element_type_id);
        log(lcc_unit || ': ln_element_link_id  =' || ln_element_link_id);
        log(lcc_unit || ': lc_el_costable_type =' || lc_el_costable_type);

        lr_ee.element_name  := xxsvb_hr_api.get_element_name(ln_element_type_id);
        lr_ee.assignment_id := ln_ass_id;
        lr_ee.attribute1    := lr_betaalverzoek.declaratienummer;
        lr_ee.attribute2    := lr_betaalverzoek.correctieop;
        lr_ee.attribute3    := lr_betaalverzoek.correctieop_type;
        lr_ee.attribute4    := lr_betaalverzoek.zorgovereenkomstnummer;


        lr_ee.effective_start_date := lr_ee.effective_date;
        lr_ee.element_link_id      := ln_element_link_id;

        log(lcc_unit || ': lr_ee.effective_date =' || lr_ee.effective_date);
        log(lcc_unit || ': lr_ee.effective_start_date =' || lr_ee.effective_start_date);

        j := 0;
        log('xxsvb_kvi_py_betverzoeknp_1_1.process_betaalverzoek Conmponent=' || lr_betaalverzoek.declaratieregels(i).component);

        if ln_iv_id_aantal_uren is not null
        then
          j := j + 1;
          lr_ee.input_value_id_tbl(j) := ln_iv_id_aantal_uren;
          lr_ee.entry_value_tbl(j) := lr_betaalverzoek.aantaluren;
          log(lcc_unit || ': lr_betaalverzoek.aantaluren=' || lr_ee.entry_value_tbl(j));
        end if;

        if ln_iv_id_totaalbedrag is not null
        then
          j := j + 1;
          lr_ee.input_value_id_tbl(j) := ln_iv_id_totaalbedrag;
          lr_ee.entry_value_tbl(j) := lr_betaalverzoek.declaratieregels(i).bedrag;
          log(lcc_unit || ': lr_betaalverzoek.totaalbedrag=' || lr_ee.entry_value_tbl(j));
        end if;

        if ln_iv_id_bedrag is not null
        then
          j := j + 1;
          lr_ee.input_value_id_tbl(j) := ln_iv_id_bedrag;
          lr_ee.entry_value_tbl(j) := lr_betaalverzoek.declaratieregels(i).bedrag;
          log(lcc_unit || ': lr_betaalverzoek.totaalbedrag=' || lr_ee.entry_value_tbl(j));
        end if;

        if ln_iv_id_incl_vakantieuren is not null
        then
          j := j + 1;
          lr_ee.input_value_id_tbl(j) := ln_iv_id_incl_vakantieuren;
          lr_ee.entry_value_tbl(j) := hr_general.decode_lookup('YES_NO'
                                                              ,case
                                                                 when lr_betaalverzoek.inclusiefvakantieuren = 'JA' then
                                                                  'Y'
                                                                 else
                                                                  'N'
                                                               end);
          log(lcc_unit || ': lr_betaalverzoek.inclusiefvakantieuren=' || lr_betaalverzoek.inclusiefvakantieuren);
        end if;

        if (ln_iv_id_salaris is not null)
        then
          j := j + 1;

          lr_ee.input_value_id_tbl(j) := ln_iv_id_salaris;
          lr_ee.entry_value_tbl(j) := lr_betaalverzoek.declaratieregels(i).bedrag;
          log(lcc_unit || ': lr_betaalverzoek.declaratieregels(i).salaris=' || lr_betaalverzoek.declaratieregels(i).bedrag);
        end if;

        if (ln_iv_id_reden is not null)
        then
          j := j + 1;

          lr_ee.input_value_id_tbl(j) := ln_iv_id_reden;
          lr_ee.entry_value_tbl(j) := lc_reden;
          log(lcc_unit || ': lc_redens=' || lc_reden);
        end if;

        if (ln_iv_id_svj_datum is not null)
        then
          j := j + 1;

          lr_ee.input_value_id_tbl(j) := ln_iv_id_svj_datum;
          lr_ee.entry_value_tbl(j) :=  ld_svj_datum ;
          log(lcc_unit || ': ld_datum_svj=' || to_char( ld_svj_datum,'dd.mm.yyyy'));
        end if;

        lr_ee.num_entry_values := j;

        --

        d := lr_betaalverzoek.declaratieregels(i).details.first;

        while d is not null
        loop

          l_cnt := l_cnt + 1;

          lr_ee.entry_information_category := lr_ee.element_name;

          case l_cnt
            when 1 then
              lr_ee.entry_information1 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information2 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 2 then
              lr_ee.entry_information3 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information4 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 3 then
              lr_ee.entry_information5 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information6 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 4 then
              lr_ee.entry_information7 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information8 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 5 then
              lr_ee.entry_information9  := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information10 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 6 then
              lr_ee.entry_information11 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information12 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 7 then
              lr_ee.entry_information13 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information14 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 8 then
              lr_ee.entry_information15 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information16 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 9 then
              lr_ee.entry_information17 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information18 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            when 10 then
              lr_ee.entry_information19 := lr_betaalverzoek.declaratieregels(i).details(d).aantal;
              lr_ee.entry_information20 := lr_betaalverzoek.declaratieregels(i).details(d).eenheid;
            else
              xxsvb_utl_custom_messaging.set_message('DPGB-F1002');
              raise xxsvb_globals.ge_error;

          end case;

          d := lr_betaalverzoek.declaratieregels(i).details.next(d);

        end loop;

        -- PF-3993 set element entry level costing segments
        if lc_el_costable_type <> 'N'
        then

  --      segment3                                                                                -- wet, wordt vooralsnog niet aangeleverd vanuit Z, de kans is groot dat de wet zal worden aangeleverd dmv het fdomein koppelvlak. Daarom voorlopig vanuit de element link gevuld.
          lr_ee.cak_segment4  := lr_betaalverzoek.declaratieperiode.declaratiejaar;               -- jaar
  --      segment7                                                                                -- verstrekker, wordt vooralsnog niet aangeleverd vanuit Z, , de kans is groot dat de verstrekker zal worden aangeleverd dmv het fdomein koppelvlak. Daarom voorlopig vanuit de element link gevuld.
          lr_ee.cak_segment11 := lpad(lr_betaalverzoek.declaratieperiode.declaratiemaand,2,'0');  -- periode
          lr_ee.cak_segment12 := lr_betaalverzoek.declaratienummer;                               -- declaratienummer

        end if;

        xxsvb_hr_api.call_create_ee_api(pr_ee            => lr_ee
                                       ,xc_return_status => lc_return_status
                                       ,xc_error_code    => xc_error_code
                                       ,xc_error_text    => xc_error_text
                                       ,xc_message       => lc_message);

        lr_ee := lr_ee_null;

        if lc_return_status <> gcc_ret_sts_success
        then
          exit; --exit loop
        end if;

        i := lr_betaalverzoek.declaratieregels.next(i);

      end loop;

      log(lcc_unit || ': End...');

    end if;

    --
    xd_verwachte_betaaldatum := get_pay_date( gcc_verloningskalender, trunc(sysdate) );

    --
    xc_return_status := lc_return_status;
    xc_error_code    := lc_error_code;
    xc_error_text    := lc_error_text;
    xc_message       := lc_message;

    xxsvb_generic_int.write_service_status(pc_message_id     => pc_message_id
                                          ,pc_service_name   => gcc_service_name --betaalverzoekNatuurlijkPersoon
                                          ,pc_return_status  => lc_return_status
                                          ,pc_error_code     => lc_error_code
                                          ,pc_error_text     => lc_error_text
                                          ,pc_status_message => lc_message
                                          ,ps_start_timestamp => ls_start_timestamp);


  exception
    when ge_warning then
      xc_return_status := gcc_ret_sts_success;
      xxsvb_utl_exceptions.raise_error(gnc_error, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xxsvb_generic_int.write_service_status(pc_message_id, gcc_service_name, xc_return_status, xc_error_code, xc_error_text, xc_message, ls_start_timestamp);

    when xxsvb_globals.ge_error then
      xc_return_status := gcc_ret_sts_unexp_error;
      xxsvb_utl_exceptions.raise_error(gnc_error, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xxsvb_generic_int.write_service_status(pc_message_id, gcc_service_name, xc_return_status, xc_error_code, xc_error_text, xc_message, ls_start_timestamp);
      xc_return_status := gcc_ret_sts_error;

    when xxsvb_globals.ge_unexpected_error then
      xc_return_status := gcc_ret_sts_unexp_error;
      xxsvb_utl_exceptions.raise_error(gnc_error, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xxsvb_generic_int.write_service_status(pc_message_id, gcc_service_name, xc_return_status, xc_error_code, xc_error_text, xc_message, ls_start_timestamp);
      xc_return_status := gcc_ret_sts_unexp_error;

    when xxsvb_globals.ge_fatal then
      xc_return_status := gcc_ret_sts_unexp_error;
      xxsvb_utl_exceptions.raise_error(gnc_error, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xxsvb_generic_int.write_service_status(pc_message_id, gcc_service_name, xc_return_status, xc_error_code, xc_error_text, xc_message);
      raise;
    when others then
      xc_return_status := gcc_ret_sts_unexp_error;
      xxsvb_utl_custom_messaging.oracle_error(sqlerrm, lcc_unit, gcc_package_name);
      xxsvb_utl_exceptions.raise_error(gnc_unexpected, gcc_package_name, lcc_unit, xc_error_code, xc_error_text, xc_message);
      xxsvb_generic_int.write_service_status(pc_message_id, gcc_service_name, xc_return_status, xc_error_code, xc_error_text, xc_message, ls_start_timestamp);

  end process_betaalverzoek;

  procedure cp_retry_service_request
  (
    pc_errbuf         out varchar2
   ,pn_retcode        out number
   ,pc_message_id     in varchar2
  )
  is

    lc_return_status varchar2(1) := 'S';
    lc_error_code varchar2(30);
    lc_error_text varchar2(2000);
    lc_message       varchar2(4000);
    lr_betaalverzoek xxsvb_kvi_py_betverzoeknp_1_1.grt_pay_betaalverzoek;
    lr_verwachte_betaaldatum date;
    lc_fnd_message varchar2(4000);
    lb_fout boolean := false;
    lc_message_id varchar2(50);



  begin

    -- check if message exists

    lc_fnd_message := xxsvb_generic_int.check_service_message_exists(gcc_service_name,pc_message_id);

    if lc_fnd_message is not null
    then
      lb_fout := true;
    end if;

    -- check of het bericht bij initiele aanlevering al succesvol was verwerkt.
    if not lb_fout
    then

      lc_fnd_message := xxsvb_generic_int.check_service_message_success(gcc_service_name,pc_message_id);

      if lc_fnd_message is not null
      then
        lb_fout := true;
      end if;

    end if;

    -- check of het bericht in een eerdere retry al succesvol was verwerkt
    if not lb_fout
    then
      lc_fnd_message := xxsvb_generic_int.check_service_message_retried(gcc_service_name,pc_message_id);

      if lc_fnd_message is not null
      then
        lb_fout := true;
      end if;

    end if;

    -- all checks ok ? doe de retry
    if not lb_fout
    then

      lr_betaalverzoek :=xxsvb_kvi_py_betverzoeknp_1_1.from_rcvd_table(pc_message_id,lc_return_status,lc_message);

      lc_message_id := pc_message_id || '+' || to_char(sysdate,'SS');

      xxsvb_kvi_py_betverzoeknp_1_1.process_betaalverzoek
      (pc_message_id => lc_message_id
      , pr_betaalverzoek => lr_betaalverzoek
      , xd_verwachte_betaaldatum  => lr_verwachte_betaaldatum
      , xc_return_status => lc_return_status
      , xc_error_code => lc_error_code
      , xc_error_text => lc_error_text
      , xc_message => lc_message
      );

      if lc_return_status = gcc_ret_sts_success
      then
        lc_fnd_message := 'Het bericht met dit message ID (' || pc_message_id || ') is succesvol aangeboden en verwerkt';
      else
        lb_fout := true;
        lc_fnd_message := substr('FOUT bij het opnieuw verwerken van message met ID ' || pc_message_id || ': '||lc_message,1,4000);
      end if;

    end if;


    if lb_fout
    then
      pc_errbuf := lc_message;
      pn_retcode := 1;
    end if;

    fnd_file.put_line( fnd_file.output,lc_fnd_message );
    fnd_file.put_line( fnd_file.log,lc_fnd_message );


  end cp_retry_service_request;


  procedure healthcheck
  (
    pr_fdomein       in  grt_pay_betaalverzoek
   ,xc_return_status out nocopy varchar2
  )  AS
  BEGIN
    xc_return_status := 'OK';
  END healthcheck;

END  xxsvb_kvi_py_betverzoeknp_1_1_tmp_dev;
