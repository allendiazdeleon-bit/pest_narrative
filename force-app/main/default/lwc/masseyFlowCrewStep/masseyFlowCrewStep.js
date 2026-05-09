import { LightningElement, api, wire, track } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { createRecord } from 'lightning/uiRecordApi';
import Alert from 'lightning/alert';
import Prompt from 'lightning/prompt';

// Static GraphQL queries — defined once for offline static analysis (Komaci).
const SA_QUERY = gql`
    query getServiceAppointment($workOrderId: ID) {
        uiapi {
            query {
                ServiceAppointment(
                    where: { ParentRecordId: { eq: $workOrderId } }
                    first: 1
                ) {
                    edges {
                        node {
                            Id
                            AppointmentNumber { value }
                        }
                    }
                }
            }
        }
    }
`;

const AR_QUERY = gql`
    query getAssignedResources($saId: ID) {
        uiapi {
            query {
                AssignedResource(
                    where: { ServiceAppointmentId: { eq: $saId } }
                    first: 50
                ) {
                    edges {
                        node {
                            Id
                            ServiceResourceId { value }
                            ServiceResource {
                                Name { value }
                                ResourceType { value }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const SR_QUERY = gql`
    query getServiceResources($searchTerm: String) {
        uiapi {
            query {
                ServiceResource(
                    where: { Name: { like: $searchTerm } }
                    first: 20
                    orderBy: { Name: { order: ASC } }
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            ResourceType { value }
                        }
                    }
                }
            }
        }
    }
`;

export default class MasseyFlowCrewStep extends LightningElement {
    @api recordId;
    @track _serviceAppointmentId = null;
    @track showAddPanel = false;
    @track _searchTerm = '';
    @track _loggedHours = {};
    @track _isAddingResource = false;
    _searchTimeout;

    // Query 1: ServiceAppointment from WorkOrder
    get saQuery() { return this.recordId ? SA_QUERY : undefined; }
    get saVariables() { return { workOrderId: this.recordId }; }

    @wire(graphql, { query: '$saQuery', variables: '$saVariables' })
    wiredSA({ data, errors }) {
        if (data) {
            const edges = data.uiapi?.query?.ServiceAppointment?.edges;
            if (edges && edges.length > 0) {
                this._serviceAppointmentId = edges[0].node.Id;
            }
        }
        if (errors) {
            console.error('[CrewStep] GraphQL error (ServiceAppointment):', JSON.stringify(errors));
        }
    }

    // Query 2: AssignedResources from ServiceAppointment
    get arQuery() { return this._serviceAppointmentId ? AR_QUERY : undefined; }
    get arVariables() { return { saId: this._serviceAppointmentId }; }

    @wire(graphql, { query: '$arQuery', variables: '$arVariables' })
    _graphqlAssignedResources;

    // Query 3: ServiceResource search (only when add panel open)
    get srQuery() { return this.showAddPanel ? SR_QUERY : undefined; }
    get srVariables() {
        const term = this._searchTerm ? `%${this._searchTerm}%` : '%';
        return { searchTerm: term };
    }

    @wire(graphql, { query: '$srQuery', variables: '$srVariables' })
    _graphqlServiceResources;

    // -------------------------------------------------------
    // Computed properties
    // -------------------------------------------------------
    get allCrewMembers() {
        if (this._graphqlAssignedResources?.errors) {
            console.error('[CrewStep] GraphQL error (AssignedResources):',
                JSON.stringify(this._graphqlAssignedResources.errors));
        }
        const edges = this._graphqlAssignedResources?.data?.uiapi?.query?.AssignedResource?.edges || [];
        return edges.map(edge => {
            const node = edge.node;
            const name = node.ServiceResource?.Name?.value || 'Unknown';
            const type = node.ServiceResource?.ResourceType?.value || '';
            const resourceId = node.ServiceResourceId?.value;
            const key = resourceId || node.Id;
            return {
                id: node.Id,
                serviceResourceId: resourceId,
                name,
                role: type,
                initials: this.getInitials(name),
                status: 'on_route',
                statusLabel: 'On Route',
                statusClass: 'badge badge-on-route',
                hours: this._loggedHours[key] || 0
            };
        });
    }

    get crewSize() { return this.allCrewMembers.length; }
    get onRouteCount() { return this.allCrewMembers.filter(m => m.status === 'on_route').length; }
    get totalHours() { return this.allCrewMembers.reduce((sum, m) => sum + (m.hours || 0), 0).toFixed(1); }
    get hasMembers() { return this.crewSize > 0; }
    get noMembers() { return !this.hasMembers; }

    get availableResources() {
        const edges = this._graphqlServiceResources?.data?.uiapi?.query?.ServiceResource?.edges || [];
        const assignedIds = new Set(this.allCrewMembers.map(m => m.serviceResourceId));
        return edges
            .map(edge => ({
                id: edge.node.Id,
                name: edge.node.Name?.value || 'Unknown',
                type: edge.node.ResourceType?.value || '',
                initials: this.getInitials(edge.node.Name?.value)
            }))
            .filter(r => !assignedIds.has(r.id));
    }

    get hasAvailableResources() { return this.availableResources.length > 0; }
    get noAvailableResources() { return !this.hasAvailableResources && this.showAddPanel; }

    // -------------------------------------------------------
    // Event handlers
    // -------------------------------------------------------
    handleAddCrewMember() {
        if (!this._serviceAppointmentId) {
            Alert.open({
                label: 'Not Available',
                message: 'No Service Appointment found for this Work Order.'
            });
            return;
        }
        this.showAddPanel = true;
        this._searchTerm = '';
    }

    handleCloseAddPanel() {
        this.showAddPanel = false;
        this._searchTerm = '';
    }

    handleSearchInput(event) {
        const value = event.target.value;
        clearTimeout(this._searchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimeout = setTimeout(() => {
            this._searchTerm = value;
        }, 300);
    }

    async handleSelectResource(event) {
        const resourceId = event.currentTarget.dataset.id;
        if (!resourceId || this._isAddingResource) return;

        this._isAddingResource = true;
        try {
            await createRecord({
                apiName: 'AssignedResource',
                fields: {
                    ServiceAppointmentId: this._serviceAppointmentId,
                    ServiceResourceId: resourceId
                }
            });
            this.showAddPanel = false;
            this._searchTerm = '';

            if (this._graphqlAssignedResources) {
                await refreshGraphQL(this._graphqlAssignedResources);
            }
        } catch (error) {
            console.error('[CrewStep] Error adding crew member:', JSON.stringify(error));
            await Alert.open({
                label: 'Error',
                message: 'Failed to add crew member.'
            });
        } finally {
            this._isAddingResource = false;
        }
    }

    async handleLogTime() {
        const result = await Prompt.open({
            label: 'Log Time',
            message: 'Enter hours worked for all techs on the route:',
            defaultValue: '0'
        });

        if (result !== null && result !== undefined) {
            const hours = parseFloat(result);
            if (!isNaN(hours) && hours >= 0) {
                const newHours = {};
                this.allCrewMembers.forEach(m => {
                    const key = m.serviceResourceId || m.id;
                    newHours[key] = hours;
                });
                this._loggedHours = { ...newHours };
            }
        }
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimeout);
    }

    getInitials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n.charAt(0)).join('').toUpperCase().substring(0, 2);
    }
}
