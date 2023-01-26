/**
 * @description       : 
 *                      
 * @author            : hyein.jeon@daeunextier.com
 * @group             :
 * @last modified on  : 2023-01-18
 * @last modified by  : hyein.jeon@daeunextier.com
 * Modifications Log
 * Ver     Date             Author               Modification
 * 1.0   2023-01-18   hyein.jeon@daeunextier.com   Initial Version
 */

public with sharing class CampaignUpdateMemberController {

    public Id recordId { get; set; }
    public Campaign campaign { get; set; }
    public Date LastUpdatedDate { get; set; }
    public List<CampaignMember> listCampMem = new List<CampaignMember>();
    public List<Campaign> listCampaign = new list<Campaign>();

    public CampaignUpdateMemberController(ApexPages.StandardController controller) {
        campaign =  (Campaign) controller.getRecord();
        recordId = campaign.Id;

        // Campaign 을 listCampaign 에 담기
        listCampaign = [
                SELECT Id, State__c, USModelCamp__c, LastUpdatedDate__c
                FROM   Campaign
                WHERE  Id =: recordId
        ];

        // Multi-picklist인 USModel를 set에 담기
        Set<String> campaignUSModel = new Set<String>();
        for(Campaign cp : listCampaign) {
            if(cp.USModelCamp__c != null) {
                // Campaign의 LastUpdatedDate__c를 LastUpdatedDate에 넣어주기
                LastUpdatedDate = cp.LastUpdatedDate__c;

                String cpUSModel = cp.USModelCamp__c;
                String[] subCpUSModel = cpUSModel.split(';');
                for (String s : subCpUSModel) {
                    campaignUSModel.add(s);
                }
            }
        }

        // Campaign USModel과 같은 USModel을 가지고 있는 product를 set에 담기
        List<Product2> listProduct2 = [
                SELECT Id, UsModel__c
                FROM   Product2
                WHERE  UsModel__c LIKE :campaignUSModel
        ];
        Set<String> setProductId = new Set<String>();
        for(Product2 p : listProduct2) {
            if(p.Id != null) {
                setProductId.add(p.Id);
            }
        }

        // 위 Product가 연결되어있는, Is Active 가 true 인 Asset 리스트
        List<Asset__c> listAsset = [
                SELECT Id, IsActive__c, Hospital__c,
                        InstallDate__c, Product__c
                FROM Asset__c
                WHERE IsActive__c = TRUE
                AND Product__c =: setProductId
                AND InstallDate__c >: LastUpdatedDate
        ];

        // 위 Asset에 연결된 Account를 set에 담기
        Set<String> setAccount = new Set<String>();
        if(!listAsset.isEmpty()) {
            for (Asset__c a : listAsset) {
                if (a.Hospital__c != null) {
                    setAccount.add(a.Hospital__c);
                }
            }
        }

        // AccountId 와 Asset__c 을 Mapping 해주기
        Map<Id, Asset__c> mapAccountAsset = new Map<Id, Asset__c>();
        if(!listAsset.isEmpty()) {
            for(Asset__c a : listAsset) {
                mapAccountAsset.put(a.Hospital__c, a);
            }
        }

        // CampaignMember 리스트
        List<CampaignMember> listCampaignMembers = new List<CampaignMember>([
                SELECT Id, ContactId
                FROM   CampaignMember
                WHERE  Campaign.Id =: recordId
        ]);

        // CampaignMember에 들어있는 Contact를 Set에 담기
        Set<String> campaignMemberIds = new Set<String>();
        for(CampaignMember cpm : listCampaignMembers){
            if(cpm.ContactId != null) {
                campaignMemberIds.add(cpm.ContactId);
            }
        }

        // Campaign Member에 넣을 Contact들 불러와서 listContact에 넣기
        List<Contact> listContact = new list<Contact>([
                SELECT Id, Role__c, LastModifiedDate, AccountId
                FROM Contact
                WHERE Id NOT IN :campaignMemberIds
                AND AccountId IN: setAccount
                ORDER BY LastModifiedDate DESC
        ]);

        // Account에 하나의 Contact만 있으면 그 하나를 넣어주고, 여러개가 있으면 Dentist 인 애들을 넣어주고,
        // Dentist가 없으면 가장 최신으로 수정된 레코드를 넣어준다.
        Map<Id, Contact> mapAccountContact = new Map<Id, Contact> ();
        if(!listContact.isEmpty()) {
            for (Contact c : listContact) {
                if (mapAccountContact.get(c.AccountId) == null) {
                    mapAccountContact.put(c.AccountId, c);
                } else {
                    if (mapAccountContact.get(c.AccountId).Role__c == 'Dentist') {
                        // LastModifiedDate가 최신인 Contact의 Role이 Dentist 이기 때문에 수정할 필요 없다.
                    } else if (mapAccountContact.get(c.AccountId).Role__c != 'Dentist' && c.Role__c == 'Dentist') {
                        // LastModifiedDate가 최신인 Contact의 Role이 Dentist가 아닌데
                        // 그 다음 Contact의 Role 이 Dentist라면 수정해주어야한다.
                        mapAccountContact.put(c.AccountId, c);
                    }
                }
            }
        }

        // Map에 있는 Contact 들을 list 에 넣어준다
        list<Contact> listContact2 = new list<Contact>();
        listContact2 = mapAccountContact.values();

        // Contact을 CampaignMember 에 넣어준다.
        if(!listContact2.isEmpty()) {
            for (Contact c : listContact2) {
                CampaignMember cm = new CampaignMember();
                cm.ContactId = c.Id;
                cm.CampaignId = recordId;
                cm.Practice__c = c.AccountId;
                cm.Asset__c = mapAccountAsset.get(c.AccountId).Id;
                listCampMem.add(cm);
            }
        }

    }

    // 원래 Campaign Record Detail page로 redirect 한다.
    public PageReference pageReference() {

        try {
            if (!listCampMem.isEmpty()) {
                insert listCampMem;
            }
        } catch (System.DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
                // Process exception here
                System.debug(e.getDmlMessage(i));
            }
        }

        // Campaign의 LastUpdatedDate__c를 Today 날짜로 바꿔준다
        for(Campaign c : listCampaign) {
            c.LastUpdatedDate__c = Date.today();
        }

        try {
            if (!listCampaign.isEmpty()) {
                update listCampaign;
            }
        } catch (System.DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
                // Process exception here
                System.debug(e.getDmlMessage(i));
            }
        }

        //build your code logic here
        PageReference pageRef = new PageReference('/' + recordId);
        pageRef.setRedirect(true);
        return pageRef; //Returns to the case page

    }

}
