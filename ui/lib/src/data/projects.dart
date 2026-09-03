import '../models/project_models.dart';

// Sample dataset containing 2 projects for each ProjectState
final List<Project> sampleProjects = [
  // ==========================================
  // 1. DRAFT (2 Projects)
  // ==========================================
  Project(
    name: 'Addis Smart Traffic Signal Expansion',
    state: ProjectState.draft,
    description: 'Installing smart traffic signals across 15 high-density intersections.',
    objective: 'Reduce peak-hour transit delays by 25%.',
    location: 'Addis Ababa, Ethiopia',
    organization: 'City Transport Authority',
    manager: 'Abebe Bikila',
    startDate: DateTime(2026, 10, 01),
    endDate: DateTime(2027, 04, 30),
  ),
  Project(
    name: 'Community Clean Water Well Project',
    state: ProjectState.draft,
    description: 'Drilling 3 deep-water wells in rural districts.',
    objective: 'Provide safe drinking water to 4,500 rural households.',
    location: 'Hawassa, Ethiopia',
    organization: 'Clean Water Initiative',
    manager: 'Bethlehem Tadesse',
    startDate: DateTime(2026, 11, 15),
    endDate: DateTime(2027, 05, 15),
  ),

  // ==========================================
  // 2. SUBMITTED (2 Projects)
  // ==========================================
  Project(
    name: 'District Solar Microgrid Phase 1',
    state: ProjectState.submitted,
    description: 'Deploying a 250kW solar mini-grid for remote health posts.',
    objective: 'Ensure uninterrupted electricity for vaccine storage.',
    location: 'Bahar Dar, Ethiopia',
    organization: 'Renewable Energy Board',
    manager: 'Chala Gemeda',
    startDate: DateTime(2026, 12, 01),
    endDate: DateTime(2027, 08, 30),
  ),
  Project(
    name: 'Youth Coding Skills Workshop',
    state: ProjectState.submitted,
    description: 'A 12-week intensive bootcamp teaching Flutter and Python.',
    objective: 'Train 200 high school graduates in practical software development.',
    location: 'Adama, Ethiopia',
    organization: 'Tech For Youth Hub',
    manager: 'Dawit Yohannes',
    startDate: DateTime(2027, 01, 10),
    endDate: DateTime(2027, 04, 10),
  ),

  // ==========================================
  // 3. UNDER REVIEW (2 Projects)
  // ==========================================
  Project(
    name: 'Urban Reforestation & Park Initiative',
    state: ProjectState.underReview,
    description: 'Planting 50,000 native trees and developing 2 public parks.',
    objective: 'Improve urban air quality and create community green zones.',
    location: 'Dire Dawa, Ethiopia',
    organization: 'Green City Foundation',
    manager: 'Eden Gebre',
    startDate: DateTime(2027, 02, 01),
    endDate: DateTime(2027, 11, 30),
  ),
  Project(
    name: 'Maternal Health Clinic Renovation',
    state: ProjectState.underReview,
    description: 'Upgrading the emergency ward and purchasing 10 new ultrasound monitors.',
    objective: 'Lower regional maternal mortality rates by 15%.',
    location: 'Mekelle, Ethiopia',
    organization: 'Regional Health Bureau',
    manager: 'Fikru Wolde',
    startDate: DateTime(2027, 01, 15),
    endDate: DateTime(2027, 07, 15),
  ),

  // ==========================================
  // 4. ACCEPTED (2 Projects)
  // ==========================================
  Project(
    name: 'Public Library Digital Archive Upgrade',
    state: ProjectState.accepted,
    description: 'Digitizing 10,000 historical documents and offering free public e-readers.',
    objective: 'Preserve cultural heritage and expand public research access.',
    location: 'Gondar, Ethiopia',
    organization: 'Heritage & Culture Ministry',
    manager: 'Getachew Assefa',
    startDate: DateTime(2026, 11, 01),
    endDate: DateTime(2027, 05, 31),
  ),
  Project(
    name: 'Highland Soil Erosion Prevention',
    state: ProjectState.accepted,
    description: 'Terracing farmland and planting deep-root grasses along valley borders.',
    objective: 'Protect 1,200 hectares of fertile farmland from washout.',
    location: 'Jimma, Ethiopia',
    organization: 'Agricultural Extension Office',
    manager: 'Helen Tekle',
    startDate: DateTime(2026, 12, 15),
    endDate: DateTime(2027, 09, 30),
  ),

  // ==========================================
  // 5. REJECTED (2 Projects)
  // ==========================================
  Project(
    name: 'Downtown Commercial Helicopter Pad',
    state: ProjectState.rejected,
    description: 'Constructing a commercial helipad atop the central square tower.',
    objective: 'Provide rapid luxury transport for executive travelers.',
    location: 'Addis Ababa, Ethiopia',
    organization: 'Apex Private Logistics',
    manager: 'Isaac Berhanu',
    startDate: DateTime(2027, 03, 01),
    endDate: DateTime(2027, 09, 01),
  ),
  Project(
    name: 'Riverbed Sand Mining Facility',
    state: ProjectState.rejected,
    description: 'Setting up industrial sand extraction along the local river basin.',
    objective: 'Supply raw concrete sand to regional real estate developers.',
    location: 'Awassa, Ethiopia',
    organization: 'Sub-Basin Extraction Co.',
    manager: 'Jamal Ahmed',
    startDate: DateTime(2027, 02, 15),
    endDate: DateTime(2027, 08, 15),
  ),

  // ==========================================
  // 6. AMENDMENT REQUESTED (2 Projects)
  // ==========================================
  Project(
    name: 'Regional Produce Cold Chain Link',
    state: ProjectState.amendmentRequested,
    description: 'Building 4 refrigerated collection centers for smallholder vegetable farmers.',
    objective: 'Reduce post-harvest food waste from 35% down to under 10%.',
    location: 'Arba Minch, Ethiopia',
    organization: 'Farmers Cooperative Union',
    manager: 'Kassahun Belay',
    startDate: DateTime(2026, 11, 01),
    endDate: DateTime(2027, 06, 30),
  ),
  Project(
    name: 'E-Government Permit Automation Portal',
    state: ProjectState.amendmentRequested,
    description: 'Web & mobile platform to process trade licenses online in 48 hours.',
    objective: 'Eliminate paper applications across 12 municipal offices.',
    location: 'Addis Ababa, Ethiopia',
    organization: 'Ministry of Innovation & Tech',
    manager: 'Lemat Haile',
    startDate: DateTime(2026, 12, 01),
    endDate: DateTime(2027, 06, 01),
  ),

  // ==========================================
  // 7. AMENDING (2 Projects)
  // ==========================================
  Project(
    name: 'Municipal Waste Recycling Plant',
    state: ProjectState.amending,
    description: 'Sorting line facility capable of processing 50 tons of plastic weekly.',
    objective: 'Divert plastic waste from city landfills into recycling pipelines.',
    location: 'Bishoftu, Ethiopia',
    organization: 'EcoClean Solutions',
    manager: 'Meron Alemu',
    startDate: DateTime(2027, 01, 01),
    endDate: DateTime(2027, 10, 31),
  ),
  Project(
    name: 'Secondary School Science Lab Equipment',
    state: ProjectState.amending,
    description: 'Outfitting 8 high school laboratories with modern chemistry tools.',
    objective: 'Improve practical STEM test results by 30%.',
    location: 'Dessie, Ethiopia',
    organization: 'Department of Education',
    manager: 'Nigist Girma',
    startDate: DateTime(2026, 11, 20),
    endDate: DateTime(2027, 04, 20),
  ),

  // ==========================================
  // 8. PREPARATION (2 Projects)
  // ==========================================
  Project(
    name: 'Rural Telemedicine Connect Pilot',
    state: ProjectState.preparation,
    description: 'Equipping 10 health centers with satellite broadband and diagnostic kits.',
    objective: 'Allow remote doctors to conduct video consultations for rural patients.',
    location: 'Jijiga, Ethiopia',
    organization: 'e-Health Alliance',
    manager: 'Oumer Hassan',
    startDate: DateTime(2026, 09, 15),
    endDate: DateTime(2027, 03, 15),
  ),
  Project(
    name: 'Artisanal Textile Weaver Export Guild',
    state: ProjectState.preparation,
    description: 'Establishing a cooperative weaving center with modern loom tools.',
    objective: 'Connect 150 local weavers to international fair-trade buyers.',
    location: 'Chencha, Ethiopia',
    organization: 'Craftsmen Guild Alliance',
    manager: 'Petros Solomon',
    startDate: DateTime(2026, 10, 01),
    endDate: DateTime(2027, 04, 01),
  ),

  // ==========================================
  // 9. ACTIVE (2 Projects)
  // ==========================================
  Project(
    name: 'City Ring Road Pedestrian Overpass',
    state: ProjectState.active,
    description: 'Construction of a steel pedestrian bridge over a 6-lane highway.',
    objective: 'Eliminate pedestrian road crossing accidents on the highway stretch.',
    location: 'Addis Ababa, Ethiopia',
    organization: 'City Roads Authority',
    manager: 'Rahel Mengistu',
    startDate: DateTime(2026, 03, 01),
    endDate: DateTime(2026, 11, 30),
  ),
  Project(
    name: 'Primary School Free Meal Program',
    state: ProjectState.active,
    description: 'Daily hot lunch distribution across 25 public primary schools.',
    objective: 'Boost school attendance rates to over 95%.',
    location: 'Harar, Ethiopia',
    organization: 'Nourish Children Trust',
    manager: 'Samson Worku',
    startDate: DateTime(2026, 01, 10),
    endDate: DateTime(2026, 12, 20),
  ),

  // ==========================================
  // 10. COMPLETED (2 Projects)
  // ==========================================
  Project(
    name: 'Central Hospital Oxygen Generator Installation',
    state: ProjectState.completed,
    description: 'Installed a high-capacity medical oxygen plant supplying 120 beds.',
    objective: 'Achieve full self-sufficiency in medical oxygen supply.',
    location: 'Hawassa, Ethiopia',
    organization: 'Central Referral Hospital',
    manager: 'Tigist Assefa',
    startDate: DateTime(2025, 06, 01),
    endDate: DateTime(2026, 02, 28),
  ),
  Project(
    name: 'Feeder Road Gravel Paving',
    state: ProjectState.completed,
    description: 'Graded and gravelled 18 kilometers of rural access road.',
    objective: 'Connect 4 farming villages to the main regional highway.',
    location: 'Wolaita Sodo, Ethiopia',
    organization: 'Rural Development Board',
    manager: 'Usman Kebede',
    startDate: DateTime(2025, 09, 01),
    endDate: DateTime(2026, 05, 15),
  ),

  // ==========================================
  // 11. CLOSED (2 Projects)
  // ==========================================
  Project(
    name: 'Community Computer Lab Phase 1',
    state: ProjectState.closed,
    description: 'Setup of 30 desktop computers and internet access in the town hall.',
    objective: 'Provide free digital access to students and job seekers.',
    location: 'Dilla, Ethiopia',
    organization: 'Digital Inclusion Fund',
    manager: 'Yonas Tilahun',
    startDate: DateTime(2024, 01, 15),
    endDate: DateTime(2024, 12, 15),
  ),
  Project(
    name: 'Emergency Drought Relief Distribution 2024',
    state: ProjectState.closed,
    description: 'Emergency food basket and water truck dispatching during severe drought.',
    objective: 'Deliver aid to 12,000 affected pastoralist families.',
    location: 'Borena, Ethiopia',
    organization: 'Disaster Risk Management',
    manager: 'Zenebe Tesfaye',
    startDate: DateTime(2024, 03, 01),
    endDate: DateTime(2024, 09, 30),
  ),
];

// Sample Review Log entries detailing audit trails for state changes
final List<ReviewAction> sampleReviewActions = [
  // Review action leading to ACCEPTED
  ReviewAction(
    previousState: ProjectState.underReview,
    newState: ProjectState.accepted,
    comment: 'All technical specifications meet municipal standards. Approved for preparation.',
    reviewerName: 'Dr. Almaz Kebede (Technical Review Board)',
    timestamp: DateTime(2026, 08, 15, 14, 30),
  ),
  // Review action leading to REJECTED
  ReviewAction(
    previousState: ProjectState.underReview,
    newState: ProjectState.rejected,
    comment: 'Fails environmental zoning compliance and presents significant noise pollution.',
    reviewerName: 'Sileshi Desta (Zoning Commissioner)',
    timestamp: DateTime(2026, 08, 20, 10, 15),
  ),
  // Review action leading to AMENDMENT REQUESTED
  ReviewAction(
    previousState: ProjectState.underReview,
    newState: ProjectState.amendmentRequested,
    comment: 'Please include detailed vendor quotes for the refrigeration units before final sign-off.',
    reviewerName: 'Mulugeta Feyissa (Finance Committee)',
    timestamp: DateTime(2026, 08, 28, 16, 45),
  ),
  // Review action leading to ACTIVE
  ReviewAction(
    previousState: ProjectState.preparation,
    newState: ProjectState.active,
    comment: 'All 7 preparation checklist items cleared. Construction work is authorized to begin.',
    reviewerName: 'Hanna Eshetu (Project Oversight Lead)',
    timestamp: DateTime(2026, 03, 01, 09, 00),
  ),
];